#!/usr/bin/env bash
# create-w10-rdp-krinix.sh
# Create a Windows 10 VM (KVM/QEMU) with:
#  - admin user (prompted)
#  - RDP enabled on port 2010
#  - host port 2010 forwarded to guest:2010
#  - KrinixRdp watermark wallpaper (Discord nightt.js / https://krinix.qzz.io)
#  - legal notice at sign-in with project/contact info
#
# USAGE: sudo ./create-w10-rdp-krinix.sh
set -euo pipefail

### ====== DEFAULT CONFIG (edit only if you want different defaults) ======
VM_NAME="KrinixRdp-vm"
RAM_MB=4096
CPU_COUNT=2
DISK_GB=50
RDP_PORT_IN_GUEST=2010
HOST_PORT_FORWARD=2010
UNATTEND_ISO_NAME="autounattend_krinix.iso"
WORKDIR="$PWD/${VM_NAME}_build"
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
LIBVIRT_NETWORK="default"
WALLPAPER_NAME="krinix_wallpaper.jpg"
# Branding text
PROJECT_NAME="KrinixRdp"
DISCORD_HANDLE="nightt.js"
WEBSITE_URL="https://krinix.qzz.io"
# =======================================================================

# Get input from user
read -rp "Full path to Windows 10 ISO (e.g. /home/me/Win10.iso): " WINDOWS_ISO
if [[ ! -f "$WINDOWS_ISO" ]]; then
  echo "ERROR: Windows ISO not found at '$WINDOWS_ISO'. Exiting."
  exit 1
fi

read -rp "VM name [${VM_NAME}]: " input_vmname
VM_NAME="${input_vmname:-$VM_NAME}"

read -rp "RAM in MB [${RAM_MB}]: " input_ram
RAM_MB="${input_ram:-$RAM_MB}"

read -rp "vCPUs [${CPU_COUNT}]: " input_cpu
CPU_COUNT="${input_cpu:-$CPU_COUNT}"

read -rp "Disk size in GB [${DISK_GB}]: " input_disk
DISK_GB="${input_disk:-$DISK_GB}"

# Prompt for admin credentials (password hidden)
read -rp "Admin username to create inside Windows: " ADMIN_USER
if [[ -z "$ADMIN_USER" ]]; then
  echo "Admin username cannot be empty. Exiting."
  exit 1
fi
read -rsp "Admin password (input hidden): " ADMIN_PASS
echo
if [[ -z "$ADMIN_PASS" ]]; then
  echo "Admin password cannot be empty. Exiting."
  exit 1
fi

echo
echo "Configuration summary:"
echo "  Windows ISO: $WINDOWS_ISO"
echo "  VM name:     $VM_NAME"
echo "  RAM:         ${RAM_MB} MB"
echo "  vCPUs:       ${CPU_COUNT}"
echo "  Disk:        ${DISK_GB} GB at ${DISK_PATH}"
echo "  Admin user:  ${ADMIN_USER}"
echo "  RDP guest port: ${RDP_PORT_IN_GUEST}"
echo "  Host forward:  ${HOST_PORT_FORWARD} -> guest:${RDP_PORT_IN_GUEST}"
echo "  Branding:     ${PROJECT_NAME}  | Discord: ${DISCORD_HANDLE}  | ${WEBSITE_URL}"
echo

# Install required packages (best-effort)
echo "Installing required packages if missing (qemu, libvirt, virt-install, genisoimage, imagemagick)..."
apt-get update -y
DEPS=(qemu-kvm libvirt-daemon-system libvirt-clients virtinst genisoimage imagemagick)
apt-get install -y "${DEPS[@]}"

# Make workdir
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Generate a simple wallpaper with watermark text using ImageMagick.
# Dimensions: 1920x1080; background gradient; big watermark centered bottom-right.
WALLPAPER_PATH="$WORKDIR/$WALLPAPER_NAME"
echo "Generating watermark wallpaper at: $WALLPAPER_PATH"
convert -size 1920x1080 gradient: -font DejaVu-Sans -pointsize 40 \
  -gravity southeast -annotate +40+40 "${PROJECT_NAME} — Discord: ${DISCORD_HANDLE} — ${WEBSITE_URL}" \
  -gravity center -pointsize 140 -annotate +0-120 "${PROJECT_NAME}" \
  "$WALLPAPER_PATH"

# Create configure.cmd which the unattend will run at first logon
# This will:
#  - create admin user & add to Administrators
#  - enable RDP (fDenyTSConnections = 0)
#  - set RDP port (PortNumber registry)
#  - allow firewall rule
#  - copy wallpaper to Public Pictures and attempt to set it as user's wallpaper
#  - set a legal notice (shown at sign-in)
cat > configure.cmd <<EOF
@echo off
REM --- KrinixRdp first-run configuration ---
REM Create user
net user "${ADMIN_USER}" "${ADMIN_PASS}" /add
net localgroup Administrators "${ADMIN_USER}" /add

REM Enable Remote Desktop
REG ADD "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f

REM Set RDP port
REG ADD "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp" /v PortNumber /t REG_DWORD /d ${RDP_PORT_IN_GUEST} /f

REM Add firewall rule for RDP port
netsh advfirewall firewall add rule name="KrinixRdp RDP ${RDP_PORT_IN_GUEST}" dir=in action=allow protocol=TCP localport=${RDP_PORT_IN_GUEST}

REM Copy wallpaper to Public Pictures for all users
mkdir "C:\\Users\\Public\\Pictures" 2>nul
copy /Y "D:\\${WALLPAPER_NAME}" "C:\\Users\\Public\\Pictures\\${WALLPAPER_NAME}"

REM Try to set wallpaper for the current user (FirstLogonCommand often runs as default user)
REG ADD "HKCU\\Control Panel\\Desktop" /v Wallpaper /t REG_SZ /d "C:\\Users\\Public\\Pictures\\${WALLPAPER_NAME}" /f
REG ADD "HKCU\\Control Panel\\Desktop" /v WallpaperStyle /t REG_SZ /d 10 /f
RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters

REM Set Legal Notice (so text appears at sign-in)
REG ADD "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System" /v legalnoticecaption /t REG_SZ /d "${PROJECT_NAME}" /f
REG ADD "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System" /v legalnoticetext /t REG_SZ /d "Project: ${PROJECT_NAME}\\nDiscord: ${DISCORD_HANDLE}\\n${WEBSITE_URL}" /f

REM Try restarting TermService to pick up port change
sc stop TermService
sc start TermService

REM Marker file
echo "KrinixRdp autoconfig completed" > C:\\krinix_autoconfig_done.txt
exit /b 0
EOF

# Create Autounattend.xml that will run configure.cmd at first logon
cat > Autounattend.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <FirstLogonCommands>
        <SynchronousCommand>
          <Order>1</Order>
          <Description>Run KrinixRdp configuration</Description>
          <CommandLine>cmd /c C:\setup\configure.cmd</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
EOF

# Prepare the ISO root: Autounattend.xml at root, wallpaper at root so configure.cmd can access D:\<wallpaper>
mkdir -p iso_root/setup
cp "$WALLPAPER_PATH" iso_root/"$WALLPAPER_NAME"
mv Autounattend.xml iso_root/Autounattend.xml
mv configure.cmd iso_root/setup/configure.cmd

# Create the autounattend ISO (Autounattend.xml must be at root and the wallpaper accessible as D:\<WALLPAPER_NAME>)
echo "Creating ${UNATTEND_ISO_NAME} (contains Autounattend.xml, configure.cmd, wallpaper)..."
genisoimage -o "${UNATTEND_ISO_NAME}" -V "AUTOUNATTEND" -J -r iso_root >/dev/null 2>&1

# Create VM disk
echo "Creating QCOW2 disk at ${DISK_PATH} (${DISK_GB}G)..."
qemu-img create -f qcow2 "$DISK_PATH" "${DISK_GB}G"

# Start the VM with the Windows ISO and the unattend ISO attached
echo "Starting VM (virt-install). This will boot the Windows ISO and use Autounattend..."
virt-install \
  --name "$VM_NAME" \
  --ram "$RAM_MB" \
  --vcpus "$CPU_COUNT" \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio,size="$DISK_GB" \
  --disk path="${UNATTEND_ISO_NAME}",device=cdrom \
  --cdrom "$WINDOWS_ISO" \
  --os-type=windows --os-variant=win10 \
  --network network="$LIBVIRT_NETWORK",model=virtio \
  --graphics spice \
  --noautoconsole \
  --wait=0

echo
echo "VM started. Windows will install using the provided Autounattend."
echo

# Try to detect the guest IP (best-effort)
echo "Waiting a bit for the VM to appear on the network..."
sleep 15
GIP=""
for i in $(seq 1 20); do
  echo "Attempt $i to detect guest IP..."
  # prefer guest agent if available
  GIP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | awk '/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $4}' | cut -d'/' -f1 || true)
  if [[ -n "$GIP" ]]; then break; fi
  # fallback to libvirt DHCP leases
  GIP=$(virsh net-dhcp-leases "$LIBVIRT_NETWORK" 2>/dev/null | awk -v vm="$VM_NAME" '$0 ~ vm {for (i=1;i<=NF;i++) if ($i ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) print $i}' | head -n1 || true)
  if [[ -n "$GIP" ]]; then break; fi
  sleep 10
done

if [[ -z "$GIP" ]]; then
  echo
  echo "Could not determine guest IP automatically. Wait until installation finishes and run:"
  echo "  virsh domifaddr ${VM_NAME} --source agent"
  echo "or check DHCP leases:"
  echo "  virsh net-dhcp-leases ${LIBVIRT_NETWORK}"
  echo
  echo "When you have the guest IP (GUEST_IP), run these commands on the Ubuntu host to forward host:2010 -> guest:2010:"
  echo "  sudo iptables -t nat -A PREROUTING -p tcp --dport ${HOST_PORT_FORWARD} -j DNAT --to-destination GUEST_IP:${RDP_PORT_IN_GUEST}"
  echo "  sudo iptables -t nat -A POSTROUTING -p tcp -d GUEST_IP --dport ${RDP_PORT_IN_GUEST} -j MASQUERADE"
  echo
  echo "Then connect with your RDP client to: <UBUNTU_HOST_IP>:${HOST_PORT_FORWARD}"
  exit 0
fi

echo "Detected guest IP: $GIP"

# Add iptables forwarding so external RDP connections to host:2010 go to the guest:2010
echo "Adding iptables NAT rules to forward ${HOST_PORT_FORWARD} -> ${GIP}:${RDP_PORT_IN_GUEST} ..."
iptables -t nat -A PREROUTING -p tcp --dport "${HOST_PORT_FORWARD}" -j DNAT --to-destination "${GIP}:${RDP_PORT_IN_GUEST}"
iptables -t nat -A POSTROUTING -p tcp -d "${GIP}" --dport "${RDP_PORT_IN_GUEST}" -j MASQUERADE

echo
echo "Port forwarding added. You can now RDP to: <UBUNTU_HOST_IP>:${HOST_PORT_FORWARD}"
echo "Login with the Windows admin account: ${ADMIN_USER} and the password you entered."
echo
echo "Branding applied: wallpaper placed at C:\\Users\\Public\\Pictures\\${WALLPAPER_NAME}"
echo "A legal notice (shown at sign-in) contains the project name and contact info."
echo
echo "SECURITY NOTE: The admin password was temporarily embedded in the ISO used during setup (plain text)."
echo "After first login, change the password immediately and remove any temporary files if you care about secrecy."
echo
echo "If RDP doesn't accept connections, verify the Windows edition supports incoming Remote Desktop and check C:\\krinix_autoconfig_done.txt on the guest to confirm the autoconfig ran."
