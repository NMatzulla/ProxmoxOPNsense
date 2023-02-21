# ProxmoxOPNsense
ProxmoxOPNsense is a basic tool which allows to install Proxmox with the OPNsense firewall on Hetzner servers.


## Overview
> **_NOTE:_**: This tool was developed for the Hetzner infrastructure. Note that **other environments may not support** this tool.

This tool helps you to install Proxmox with OPNsense firewall. This tool routes the host IPv4 address to all virtual machines. Each virtual machine gets an additional IPv6 address from the /64 subnet.


## Usage
Run the following command to download and run this tool:

```bash
bash <(wget --no-check-certificate -O - 'https://raw.githubusercontent.com/NMatzulla/ProxmoxOPNsense/master/setup.sh')
```


### Required configuration steps
During the installation, you will be prompted to perform additional steps or confirm processes.


#### Postfix configuration
Postfix is used by Proxmox for email communication. By default, you can set up Postfix locally by selecting `Local only`. In the following window the input field of `System mail name` should be `proxmox.your-domain.tld` (`your-domain.tld` should represent your domain name), if this is not so correct this manually. You can use the `Satellite system` to connect your existing mail server to Proxmox. The [official documentation of Postfix](https://www.postfix.org/documentation.html) can optionally help you with the setup.

#### Removal confirmation
Proxmox uses its own kernel, the default kernel is unused and can be removed. Confirm this operation by pressing `No`.

## Setup of OPNsense
The OPNsense setup is not implemented in this tool. Read the [official documentation](https://docs.opnsense.org) for setup instructions.

# License
This project is licensed under the MIT license. All terms and conditions can be found in the [LICENSE file](./LICENSE) of this repository.

# Sources
This project was made possible by the following projects:
- 21.02.2023: [Proxmox offizielle Dokumentation](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_11_Bullseye)
- 21.02.2023: [OpnSense auf Proxmox installieren: Nur 1 IP [Hetzner Server]](https://www.youtube.com/watch?v=uKGkw7KE0ng)
- 21.02.2023: [OpnSense auf Proxmox: IPv6 Setup [Hetzner Server]](https://www.youtube.com/watch?v=GhaGO83VIz0)