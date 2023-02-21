#!/bin/bash

#
# Copyright (c) 2023 Nicklas Matzulla
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

ipv6_prefix=$(ip -6 addr | awk '{print $2}' | grep -P '^(?!fe80)[[:alnum:]]{4}:.*/64'| awk -F "::" '{print $1; exit}')
function generate_ipv6_address() {
    interface_id=$(for ((i=0;i<4;i++)); do printf "%02x%02x:" $((RANDOM%256)) $((RANDOM%256)); done | sed 's/:$//')
    echo "$ipv6_prefix:$interface_id"
}

network_interface=$(ip -br l | awk '$1 !~ "lo|vir|wl" { print $1; exit}')
ipv6_host_address=$(generate_ipv6_address)
ipv6_opnsense_gateway_address=$(generate_ipv6_address | awk -F ":" '{print $1":"$2":"$3":"$4":"$5":"$6":"$7":0c58"}')
ipv6_opnsense_vm_address=$(echo "$ipv6_opnsense_gateway_address" | awk -F ":" '{print $1":"$2":"$3":"$4":"$5":"$6":"$7":0c59"}')
ipv6_gateway=$(ip -6 route | grep default | awk '{print $3; exit}')
ipv4_address=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | awk -F "/" '{print $1; exit}')
ipv4_cidr=$(ip -o -f inet addr show | awk '/scope global/ {print $4; exit}')
ipv4_gateway=$(route -n | grep 'UG[ \t]' | awk '{print $2; exit}')

function update() {
    apt update
    apt dist-upgrade -y
}


function update_network_configuration() {
    apt install -y openvswitch-switch
    hostnamectl set-hostname "proxmox.$1"
    rm /etc/hosts
    {
        echo "127.0.0.1 localhost.localdomain localhost"
        echo "$ipv4_address proxmox.$domain proxmox"
        echo "::1 ip6-localhost ip6-loopback"
        echo "fe00::0 ip6-localnet"
        echo "ff00::0 ip6-mcastprefix"
        echo "ff02::1 ip6-allnodes"
        echo "ff02::2 ip6-allrouters"
        echo "ff02::3 ip6-allhosts"
        echo "$ipv6_host_address proxmox.$domain proxmox"
    } >> /etc/hosts
    rm /etc/network/interfaces
    {
        echo "auto lo"
        echo "iface lo inet loopback"
        echo "iface lo inet6 loopback"
        echo ""
        echo "auto $network_interface"
        echo "iface $network_interface inet static"
        echo "  address $ipv4_cidr"
        echo "  gateway $ipv4_gateway"
        echo "  post-up   sysctl -w net.ipv4.ip_forward=1"
        echo "  post-up   sysctl -w net.ipv6.conf.all.forwarding=1"
        echo "  post-up   iptables -t nat -A PREROUTING -i eno1 -j DNAT --to 10.10.10.1"
        echo "  post-down iptables -t nat -D PREROUTING -i eno1 -j DNAT --to 10.10.10.1"
        echo ""
        echo "iface eno1 inet6 static"
        echo "  address $ipv6_host_address/128"
        echo "  gateway $ipv6_gateway"
        echo ""
        echo "auto vmbr0"
        echo "iface vmbr0 inet static"
        echo "  address 10.10.10.0/31"
        echo "  bridge-ports none"
        echo "  bridge-stp off"
        echo "  bridge-fd 0"
        echo "  post-up   iptables -t nat -A POSTROUTING -s '10.10.10.1/31' -o eno1 -j MASQUERADE"
        echo "  post-down iptables -t nat -D POSTROUTING -s '10.10.10.1/31' -o eno1 -j MASQUERADE"
        echo "# OPNsense WAN"
        echo ""
        echo "iface vmbr0 inet6 static"
        echo "  address $ipv6_opnsense_gateway_address/127"
        echo "  up ip route add $ipv6_prefix::/64 via $ipv6_opnsense_vm_address"
        echo ""
        echo "auto vmbr1"
        echo "iface vmbr1 inet manual"
        echo "  ovs_type OVSBridge"
        echo "# VM NET"
    } >> /etc/network/interfaces
}

function install_s1() {
    update
    echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bullseye pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
    wget https://enterprise.proxmox.com/debian/proxmox-release-bullseye.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg
    update
    apt install -y pve-kernel-5.15
}

function install_s2 {
    update_network_configuration "$1"
#    service networking restart
    apt install -y proxmox-ve postfix open-iscsi nginx
    apt remove linux-image-amd64 'linux-image-5.10*' -y
    update-grub
    rm /etc/nginx/sites-enabled/default
    {
        echo "upstream proxmox {"
        echo "  server \"proxmox.$1\";"
        echo "}"
        echo ""
        echo "server {"
        echo "  listen [::]:80 default_server;"
        echo "  rewrite ^(.*) https://\$host$1 permanent;"
        echo "}"
        echo ""
        echo "server {"
        echo "  listen [::]:443 ssl;"
        echo "  server_name _;"
        echo "  ssl_certificate /etc/pve/local/pve-ssl.pem;"
        echo "  ssl_certificate_key /etc/pve/local/pve-ssl.key;"
        echo "  proxy_redirect off;"
        echo "  location / {"
        echo "    proxy_http_version 1.1;"
        echo "    proxy_set_header Upgrade \$http_upgrade;"
        echo "    proxy_set_header Connection \"upgrade\";"
        echo "    proxy_pass https://localhost:8006;"
        echo "    proxy_buffering off;"
        echo "    client_max_body_size 0;"
        echo "    proxy_connect_timeout  3600s;"
        echo "    proxy_read_timeout  3600s;"
        echo "    proxy_send_timeout  3600s;"
        echo "    send_timeout  3600s;"
        echo "  }"
        echo "}"
    } >> /etc/nginx/conf.d/proxmox.conf
}

# shellcheck disable=SC2086
function restart_server() {
    countdown=$1
    REWRITE="\e[25D\e[1A\e[K"
    echo "Server restart in $countdown..."
    while [ $countdown -gt 0 ]; do
        countdown=$((countdown-1))
        sleep 1
        echo -e "${REWRITE}Server restart in $countdown..."
    done
    echo -e "${REWRITE}Server is being rebooted..."
    reboot
}

function install() {
#    clear
    if [ -f "/root/.setup/installation_step_2" ]; then
        echo "You have already completed the installation!"
        exit
    fi
    if [ -f "/root/.setup/installation_step_1" ]; then
        echo "What is your domain (e.g. domain.tld)?"
        read -r -p "Domain: " domain
        mkdir -p /root/.setup/ ; touch /root/.setup/installation_step_2
        install_s2 "$domain"
#        clear
        echo "The installation was completed, some changes were made to the system. You are no longer able to log in via IPv4."
        echo ""
        echo ""
        echo "IPv6 CREDENTIALS:"
        echo ">   Host CIDR:             $ipv6_host_address/128"
        echo ">   OPNsense gateway CIDR: $ipv6_opnsense_gateway_address/127"
        echo ">   OPNsense CIDR:         $ipv6_opnsense_vm_address/127"
        echo ""
        echo "IPv4 CREDENTIALS:"
        echo ">   Host CIDR:             $ipv4_cidr"
        echo ""
        echo "ADMINISTRATION INTERFACE:"
        echo "https://[$ipv6_host_address]"
        echo ""
        echo ""
        echo ""
        echo "The server must be restarted for changes to be applied."
        echo "After the restart you can enter the administration interface."
        echo ""
        restart_server 30
    else
        mkdir -p /root/.setup/ ; touch /root/.setup/installation_step_1
        install_s1
#        clear
        echo "The server must be restarted, run this tool again after the restart."
        echo ""
        restart_server 10
    fi
}

function main() {
    if [ "$EUID" -ne 0 ]
        then echo "Please run this tool as root user!"
        exit
    fi
#    clear
    echo "Select a number to perform the described action!"
    echo ">   1 - Start the installation and setup of services"
    echo ">   2 - Generate a random IPv6 address"
    echo ""
    read -r -p "Option: " option
    if [ "$option" == "1" ]; then
        install
    elif [ "$option" == "2" ]; then
#        clear
        echo "Generated IPv6 address: $(generate_ipv6_address)"
    fi
}

main