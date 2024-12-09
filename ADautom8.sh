#!/bin/bash

# Comprehensive Samba AD DC Setup Script
# Automates the setup of a Samba Active Directory Domain Controller (AD DC).
# Includes installation, configuration, troubleshooting, and validation steps.

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Function to install required packages
install_packages() {
    echo "Installing required packages with pacman..."
    pacman -Syu --noconfirm samba krb5 bind-tools dnsutils net-tools dnsmasq python-pip
    echo "Installing Python packages with pip..."
    pip install markdown pygments
}

# Function to handle potential DNS conflicts
disable_dnsmasq() {
    echo "Checking for DNS conflicts with dnsmasq..."
    if systemctl is-active --quiet dnsmasq; then
        echo "dnsmasq is running. Disabling and stopping it..."
        systemctl disable dnsmasq
        systemctl stop dnsmasq
    else
        echo "dnsmasq is not running. No action needed."
    fi
}

# Function to configure /etc/krb5.conf
configure_kerberos() {
    echo "Configuring Kerberos (krb5.conf)..."
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
    echo "Kerberos configuration complete."
}

# Prompt user for FQDN, Realm, and DNS forwarder
setup_prompt() {
    echo "Welcome to the Samba AD DC Full Setup Script!"
    echo
    read -p "Enter the FQDN for your server (e.g., dc.example.com): " FQDN
    if [[ -z "$FQDN" ]]; then
        echo "FQDN cannot be empty. Exiting."
        exit 1
    fi
    echo "FQDN set to: $FQDN"

    DOMAIN=$(echo "$FQDN" | awk -F. '{print $2"."$3}')
    REALM=$(echo "$DOMAIN" | tr 'a-z' 'A-Z')

    read -p "Enter the DNS forwarder (e.g., 8.8.8.8): " DNS_FORWARDER
    if [[ -z "$DNS_FORWARDER" ]]; then
        echo "DNS forwarder cannot be empty. Exiting."
        exit 1
    fi
    echo "DNS forwarder set to: $DNS_FORWARDER"
}

# Function to configure Samba
configure_samba() {
    echo "Configuring Samba..."
    cat <<EOL > /etc/samba/smb.conf
[global]
    netbios name = $(hostname)
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
    echo "Samba configuration file created at /etc/samba/smb.conf."
}

# Function to provision the Samba AD DC
provision_samba() {
    echo "Provisioning the Samba AD Domain Controller..."
    rm -rf /var/lib/samba/*  # Clear any existing configuration
    samba-tool domain provision --use-rfc2307 --realm=$REALM --domain=${REALM%%.*} --server-role=dc --dns-backend=SAMBA_INTERNAL
    echo "Provisioning complete."
}

# Function to start Samba service
start_samba_service() {
    echo "Starting and enabling Samba service..."
    systemctl enable samba
    systemctl start samba

    if systemctl is-active --quiet samba; then
        echo "Samba service is running."
    else
        echo "Samba service failed to start. Check logs for details."
        exit 1
    fi
}

# Function to create a Domain Admin user
create_admin_user() {
    read -p "Would you like to create a Domain Admin user? (yes/no): " CREATE_USER
    if [[ "$CREATE_USER" == "yes" ]]; then
        read -p "Enter the username for the Domain Admin (e.g., adminuser): " ADMIN_USER
        if [[ -z "$ADMIN_USER" ]]; then
            echo "Username cannot be empty. Exiting."
            exit 1
        fi

        # Create the user
        samba-tool user create "$ADMIN_USER"
        # Add the user to Domain Admins group
        samba-tool group addmembers "Domain Admins" "$ADMIN_USER"
        echo "Domain Admin user '$ADMIN_USER' created and added to Domain Admins group."
    fi
}

# Function to test DNS
test_dns() {
    echo "Testing DNS resolution..."
    dig @$FQDN $REALM
    if [[ $? -ne 0 ]]; then
        echo "DNS resolution test failed. Check your Samba DNS configuration."
    else
        echo "DNS resolution test successful."
    fi
}

# Troubleshooting tips
troubleshooting() {
    echo "TROUBLESHOOTING TIPS:"
    echo "- Check Samba logs: journalctl -xeu samba"
    echo "- Verify DNS setup: dig @$FQDN $REALM"
    echo "- Test Kerberos: kinit administrator@$REALM"
    echo "- Confirm Samba status: systemctl status samba"
    echo "- Disable conflicting services (e.g., dnsmasq)."
    echo "- Ensure the system hostname matches the configured FQDN."
    echo
}

# Main script execution
setup_prompt
install_packages
disable_dnsmasq
configure_kerberos
configure_samba
provision_samba
start_samba_service
create_admin_user
test_dns
troubleshooting

echo
echo "Setup complete! Test your domain configuration and connect clients as needed."
