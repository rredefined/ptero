#!/bin/bash

# Blueprint Auto Installer
# Made by NighT
# Discord: https://discord.gg/HnvD2yQd

echo "======================================="
echo "     Blueprint Auto Installer"
echo "          Made by NighT"
echo "     Discord: https://discord.gg/HnvD2yQd"
echo "======================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Try: sudo ./install_blueprint.sh"
   exit 1
fi

# Detect OS
if [ -f /etc/debian_version ]; then
    OS="debian/ubuntu"
else
    echo "Unsupported OS. This script supports Debian/Ubuntu only."
    exit 1
fi

echo "Detected OS: $OS"

# Update package list
echo "Updating package list..."
apt update -y

# Install dependencies
echo "Installing dependencies..."
apt install -y curl wget git build-essential

# Install Blueprint
echo "Installing Blueprint..."
# Replace the following with the actual Blueprint installation steps
# Example placeholder: cloning a repo
if [ ! -d "/opt/blueprint" ]; then
    git clone https://github.com/your-blueprint-repo/blueprint.git /opt/blueprint
    cd /opt/blueprint || exit
    # Example build step, replace as needed
    ./install.sh
else
    echo "Blueprint already installed in /opt/blueprint"
fi

echo "======================================="
echo " Blueprint installation completed!"
echo " Made by NighT | Discord: https://discord.gg/HnvD2yQd"
echo "======================================="
