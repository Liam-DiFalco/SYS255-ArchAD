#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Prompt user for FQDN, Realm, DNS forwarder, NetBIOS name, and DNS backend
setup_prompt() {
    echo "Welcome to the Samba AD DC Setup Script!"
    
    # Get user input for the FQDN
    read -p "Enter the FQDN for your server (e.g., dc.example.com): " FQDN
    if [[ -z "$FQDN" ]]; then
        echo "FQDN cannot be empty. Exiting."
        exit 1
    fi

    DOMAIN=$(echo "$FQDN" | awk -F. '{print $2"."$3}')
    REALM=$(echo "$DOMAIN" | tr 'a-z' 'A-Z')

    # Get user input for DNS forwarder
    read -p "Enter the DNS forwarder (e.g., 8.8.8.8): " DNS_FORWARDER
    if [[ -z "$DNS_FORWARDER" ]]; then
        echo "DNS forwarder cannot be empty. Exiting."
        exit 1
    fi

    # Get user input for NetBIOS name
    read -p "Enter the NetBIOS name (short name, e.g., LIAM): " NETBIOS_NAME
    if [[ -z "$NETBIOS_NAME" ]]; then
        echo "NetBIOS name cannot be empty. Exiting."
        exit 1
    fi

    # Get user input for DNS backend (always BIND9 DLZ)
    DNS_BACKEND="BIND9_DLZ"
}

# Install required packages
install_packages() {
    echo "Installing required packages..."
    pacman -Syu --noconfirm samba krb5 bind dnsutils net-tools python-pip python-dnspython
    pip install markdown pygments --break-system-packages
}

# Configure /etc/hosts and hostname
configure_hostname() {
    echo "Configuring hostname and /etc/hosts..."
    hostnamectl set-hostname $FQDN
    cat <<EOL > /etc/hosts
127.0.0.1   localhost
192.168.1.108 $FQDN $(hostname)
EOL
}

# Configure Kerberos
configure_kerberos() {
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
}

# Configure Samba
configure_samba() {
    echo "Configuring Samba..."
    cat <<EOL > /etc/samba/smb.conf
[global]
    netbios name = $NETBIOS_NAME
    realm = $REALM
    workgroup = ${REALM%%.*}
    server role = active directory domain controller
    dns forwarder = $DNS_FORWARDER

[netlogon]
    path = /var/lib/samba/sysvol/${REALM,,}/scripts
    read only = No

[sysvol]
    path = /var/lib/samba/sysvol
    read only = No
EOL
}

# Configure BIND9 DLZ as DNS backend
configure_bind() {
    echo "Configuring BIND as DNS backend for Samba..."
    
    cat <<EOL > /etc/named.conf
options {
    directory "/var/named";
    allow-query { any; };
    recursion yes;
    forwarders { $DNS_FORWARDER; };
    dnssec-validation no;
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOL

    # Set permissions and restart BIND
    chmod 755 /var/named
    systemctl enable named
    systemctl restart named
}

# Clean existing Samba data and provision the domain
provision_samba() {
    echo "Cleaning existing Samba data..."
    rm -rf /var/lib/samba/*

    echo "Provisioning Samba AD DC with BIND9 DLZ as DNS backend..."
    samba-tool domain provision --use-rfc2307 --realm=$REALM --domain=${REALM%%.*} --server-role=dc --dns-backend=BIND9_DLZ --adminpass="Passw0rd!" || {
        echo "Provisioning failed. Check logs for details."
        exit 1
    }

    echo "Updating BIND configuration with Samba DLZ module..."
    cat <<EOL >> /etc/named.conf
dlz "$REALM" {
    database "dlopen /usr/lib/samba/bind9/dlz_bind9_9.so";
};
EOL

    systemctl restart named
}

# Set permissions
fix_permissions() {
    echo "Setting correct permissions for Samba directories..."
    chown -R root:root /var/lib/samba
    chmod -R 700 /var/lib/samba/private
}

# Start Samba service
start_samba_service() {
    echo "Starting Samba service..."
    systemctl enable samba || echo "Failed to enable Samba service."
    systemctl start samba || {
        echo "Samba service failed to start. Check logs with: journalctl -xeu samba"
        exit 1
    }
}

# Troubleshooting tips
troubleshooting() {
    echo "TROUBLESHOOTING TIPS:"
    echo "- Check Samba logs: journalctl -xeu samba"
    echo "- Verify DNS: samba-tool dns query 127.0.0.1 $DOMAIN @ ALL"
    echo "- Test Kerberos: kinit administrator@$REALM"
    echo "- Check hostname and /etc/hosts configuration."
    echo "- Check DNS resolution with 'host $FQDN' and 'host $REALM'."
}

# Main script execution
setup_prompt
install_packages
configure_hostname
configure_kerberos
configure_samba
configure_bind
provision_samba
fix_permissions
start_samba_service
troubleshooting

echo
echo "Setup complete! Test your domain and connect clients as needed."
