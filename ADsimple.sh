#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Install necessary packages
echo "Installing necessary packages..."
pacman -Syu --noconfirm samba krb5 bind dnsutils

# Configure Kerberos (create /etc/krb5.conf)
echo "Configuring Kerberos..."
cat <<EOL > /etc/krb5.conf
[libdefaults]
    default_realm = EXAMPLE.COM
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    EXAMPLE.COM = {
        kdc = dc.example.com
        admin_server = dc.example.com
    }

[domain_realm]
    .example.com = EXAMPLE.COM
    example.com = EXAMPLE.COM
EOL

# Configure Samba (simple smb.conf)
echo "Configuring Samba..."
cat <<EOL > /etc/samba/smb.conf
[global]
    workgroup = EXAMPLE
    realm = EXAMPLE.COM
    server role = active directory domain controller
    dns forwarder = 8.8.8.8

[netlogon]
    path = /var/lib/samba/sysvol/example.com/scripts
    read only = No

[sysvol]
    path = /var/lib/samba/sysvol
    read only = No
EOL

# Provision Samba AD DC with interactive mode
echo "Provisioning Samba domain with interactive mode..."
samba-tool domain provision --use-rfc2307 --realm=EXAMPLE.COM --domain=EXAMPLE --server-role=dc --dns-backend=BIND9_DLZ --interactive

# Configure BIND9 (DNS)
echo "Configuring BIND9 as DNS backend for Samba..."
cat <<EOL > /etc/named.conf
options {
    directory "/var/named";
    allow-query { any; };
    recursion yes;
    forwarders { 8.8.8.8; };
    dnssec-validation no;
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOL

systemctl enable named
systemctl restart named

# Start Samba service
echo "Starting Samba service..."
systemctl enable samba
systemctl start samba

echo "Samba AD DC setup complete!"
