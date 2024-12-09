#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Prompt user for FQDN, Realm, DNS forwarder, NetBIOS name, and DNS backend
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
    
    DNS_BACKEND="BIND9"
}

setup_prompt

# Install necessary packages
pacman -Syu samba smbclient krb5 bind --noconfirm || { echo "Failed to install packages." ; exit 1; }

# Configure Samba for AD DC
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
echo "[global]
workgroup = $DOMAIN
realm = $REALM
server string = %h server (Samba, Arch Linux)
netbios name = $NETBIOS_NAME
security = ADS
dns forwarder = $DNS_FORWARDER
server role = active directory domain controller
log file = /var/log/samba/%m.log
max log size = 1000
log level = 1

[netlogon]
    path = /var/lib/samba/sysvol/$DOMAIN/scripts
    read only = No

[sysvol]
    path = /var/lib/samba/sysvol
    read only = No" > /etc/samba/smb.conf

# Initialize the Kerberos database and realm
echo "Initializing Kerberos..."
echo "$REALM" | kinit admin
kadmin -p admin -w password -q "add_principal -pw password krbtgt/$REALM"
kadmin -p admin -w password -q "ktadd krbtgt/$REALM"

# Start Samba services
echo "Starting Samba services..."
systemctl enable smb.service
systemctl start smb.service
systemctl enable nmb.service
systemctl start nmb.service

# Configure DNS (BIND9)
echo "Configuring BIND9..."
echo "zone \"$DOMAIN\" {
    type master;
    file \"/etc/bind/db.$DOMAIN\";
};" > /etc/bind/named.conf.local

cp /etc/bind/db.empty /etc/bind/db.$DOMAIN
sed -i "s/example.com/$DOMAIN/" /etc/bind/db.$DOMAIN
echo "@ IN SOA ns1.$DOMAIN. root.$DOMAIN. (
    2023040101 ; serial
    86400      ; refresh every 24 hours
    3600       ; retry in one hour
    604800     ; expire in a week
    86400 )    ; minimum TTL of one day
;
@ IN NS ns1.$DOMAIN.
ns1 IN A $FQDN
$FQDN IN CNAME @
" > /etc/bind/db.$DOMAIN

systemctl enable named.service
systemctl start named.service

# Configure NSS for Samba
echo "hosts: files dns myhostname" >> /etc/nsswitch.conf
echo "networks: files dns" >> /etc/nsswitch.conf

echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" >> /etc/pam.d/system-auth
echo "session optional pam_systemd.so" >> /etc/pam.d/system-auth

# Restart Samba service to apply changes
echo "Restarting Samba services..."
systemctl restart smb.service

# Completion message
echo "Active Directory Domain Controller setup completed successfully!"

# Troubleshooting tips
echo "If you encounter any issues, check the following logs:"
echo "- Samba logs: /var/log/samba/"
echo "- Kerberos logs: /var/log/krb5kdc.log"
echo "- BIND9 logs: /var/log/named.log"
echo "- Check DNS resolution with: samba-tool dns query 127.0.0.1 $DOMAIN"
