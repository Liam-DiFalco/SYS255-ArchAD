#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Prompt user for FQDN, Realm, DNS forwarder, and NetBIOS name
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
    read -p "Enter the NetBIOS name (short name, e.g., LIAM): " NETBIOS
