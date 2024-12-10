#!/bin/bash

# Prompt user for domain, workgroup, and IP address
read -p "Enter the domain name: " domain
read -p "Enter the workgroup (realm): " wg
read -p "Enter the IP address of your machine: " ip

# Check if IP address is provided
if [ -z "$ip" ]; then
    echo "Error: IP address is required."
    exit 1
fi

echo "Using IP: $ip"

# Install necessary packages
sudo pacman -Syu --noconfirm samba smbclient krb5 dnsmasq python-pip

# Install Python dependencies
sudo pip install cryptography --break-system-packages
sudo pip install markdown --break-system-packages

# Configure smb.conf with user input
echo "[global]
    netbios name = SAMBADC
    realm = $domain
    workgroup = $wg
    server role = active directory domain controller
    dns forwarder = 8.8.8.8

[netlogon]
    path = /var/lib/samba/sysvol/$domain/scripts
    read only = No

[sysvol]
    path = /var/lib/samba/sysvol
    read only = No" | sudo tee /etc/samba/smb.conf

# Configure krb5.conf with user input and provided IP address
echo "[libdefaults]
    default_realm = $domain
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    $domain = {
        kdc = $ip
        admin_server = $ip
    }

[domain_realm]
    .$domain = $domain
    $domain = $domain" | sudo tee /etc/krb5.conf

# Provision Samba domain
sudo samba-tool domain provision --use-rfc2307 --interactive

# Enable Samba service
sudo systemctl enable samba
sudo systemctl restart samba

# Show domain level
sudo samba-tool domain level show
