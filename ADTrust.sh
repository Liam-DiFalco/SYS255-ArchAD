#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Prompt user for domain information
setup_prompt() {
    read -p "Enter the Fully Qualified Domain Name (FQDN) of your server: " FQDN
    if [[ -z "$FQDN" ]]; then
        echo "FQDN cannot be empty. Exiting."
        exit 1
    fi

    DOMAIN=$(echo "$FQDN" | awk -F. '{print $2"."$3}')
    REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

    read -p "Enter the DNS forwarder (e.g., 8.8.8.8): " DNS_FORWARDER
    if [[ -z "$DNS_FORWARDER" ]]; then
        echo "DNS forwarder cannot be empty. Exiting."
        exit 1
    fi

    read -p "Enter the NetBIOS name: " NETBIOS_NAME
    if [[ -z "$NETBIOS_NAME" ]]; then
        echo "NetBIOS name cannot be empty. Exiting."
        exit 1
    fi
}

setup_prompt

# Install required packages
pacman -Syu samba smbclient krb5 bind --noconfirm || { echo "Failed to install packages." ; exit 1; }

# Configure Samba smb.conf file
echo "Configuring Samba..."
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
cat <<EOF > /etc/samba/smb.conf
[global]
    workgroup = $DOMAIN
    realm = $REALM
    server string = %h server (Samba, Arch Linux)
    netbios name = $NETBIOS_NAME
    security = ADS
    dns forwarder = $DNS_FORWARDER
    log file = /var/log/samba/log.%m
    max log size = 50
    winbind use default domain = yes
    idmap config * : backend = tdb
    idmap config * : range = 1000-9999
    idmap config $REALM : backend = rid
    idmap config $REALM : range = 10000-999999
    passdb backend = tdbsam
    ldap ssl = no
    map to guest = Bad User
    wins support = yes

[netlogon]
    path = /var/lib/samba/sysvol/$REALM/scripts
    read only = No

[sysvol]
    path = /var/lib/samba/sysvol
    read only = No
EOF

# Configure Kerberos
echo "Configuring Kerberos..."
cat <<EOL > /etc/krb5.conf
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    $REALM = {
        kdc = $FQDN
        admin_server = $FQDN
    }

[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
EOL

# Provision Samba as an Active Directory Domain Controller
echo "Provisioning Samba as AD Domain Controller..."
samba-tool domain provision --use-rfc2307 --interactive || { echo "Domain provisioning failed."; exit 1; }

# Start and enable Samba services
echo "Starting Samba services..."
systemctl enable samba
systemctl start samba

systemctl enable nmb
systemctl start nmb

systemctl enable winbind
systemctl start winbind

# Configure DNS for Samba (if needed)
echo "Configuring Samba DNS..."
samba-tool dns zonecreate $FQDN $DOMAIN || { echo "Failed to create DNS zone."; exit 1; }

# Enable and start the BIND9 service (for DNS resolution)
systemctl enable named
systemctl start named

# Configuring NSS for Winbind (allow users to authenticate)
echo "Configuring NSS for Winbind..."
echo "hosts: files dns myhostname" >> /etc/nsswitch.conf
echo "networks: files dns" >> /etc/nsswitch.conf
echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" >> /etc/pam.d/system-auth
echo "session optional pam_systemd.so" >> /etc/pam.d/system-auth

# Restart winbind service to apply changes
systemctl restart winbind

echo "Active Directory Domain Controller setup completed successfully!"
