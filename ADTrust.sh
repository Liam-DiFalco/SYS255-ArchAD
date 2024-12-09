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
apt update && apt install samba smbclient winbind libnss-winbind libpam-winbind krb5-user bind9 -y || { echo "Failed to install packages." ; exit 1; }

# Configure Samba for AD DC
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
echo "[global]
workgroup = $DOMAIN
realm = $REALM
server string = %h server (Samba, Ubuntu)
netbios name = $NETBIOS_NAME
security = ADS
dns proxy = no
kerberos method = system keytab
template homedir = /home/samba/%u
template shell = /bin/bash
ldap password sync = Yes
passdb backend = tdbsam
idmap config * : backend = tdb2
idmap cache time = 30" > /etc/samba/smb.conf

# Configure Kerberos
cp /etc/krb5.conf /etc/krb5.conf.bak
echo "[logging]
 default = FILE:/var/log/kerberos.log
[libdefaults]
 default_realm = $REALM
 dns_lookup_realm = false
 dns_lookup_kdc = true
 ticket_lifetime = 24h
 forwardable = true
[realms]
 $REALM = {
 kdc = $FQDN
 admin_server = $FQDN
 default_domain = $DOMAIN
 }
 [domain_realm]
 .$DOMAIN = $REALM
 $DOMAIN = $REALM" > /etc/krb5.conf

# Configure BIND9 for Samba AD DC
cp /etc/bind/named.conf.local /etc/bind/named.conf.local.bak
echo "zone \"$DOMAIN\" {
 type master;
 file \"/etc/bind/db.$DOMAIN\";
};" > /etc/bind/named.conf.local

# Create the BIND9 zone file
cp /etc/bind/db.template /etc/bind/db.$DOMAIN
sed -i "s/example.com/$DOMAIN/" /etc/bind/db.$DOMAIN
sed -i "s/ns1.example.com/$FQDN/" /etc/bind/db.$DOMAIN

# Restart services
systemctl restart samba-ad-dc || { echo "Failed to restart Samba service." ; exit 1; }
systemctl restart bind9 || { echo "Failed to restart BIND9 service." ; exit 1; }

echo "Samba AD DC with BIND9 as DNS backend has been set up successfully!"
