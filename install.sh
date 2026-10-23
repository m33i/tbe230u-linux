#!/bin/bash
# Offline installer for the TP-Link Archer TBE230U Wi-Fi driver (Realtek RTL8912AU)
# on Ubuntu 22.04 / 24.04.   Usage:  sudo bash install.sh
set -u

DRV_NAME=rtw89
DRV_VER=7.3
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=/tmp/tbe230u-install
LOG=/var/log/tbe230u-install.log

green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()   { red "ERROR: $*"; echo "Full log: $LOG"; exit 1; }

[ "$(id -u)" -eq 0 ] || { echo "Run:  sudo bash $0"; exit 1; }
exec > >(tee -a "$LOG") 2>&1
echo "---- $(date) ----"

# 1. System checks ---------------------------------------------------------
step "Checking system"
. /etc/os-release
KVER="$(uname -r)"
echo "System: $PRETTY_NAME   Kernel: $KVER"
case "$VERSION_ID" in
  22.*) REPO=ubuntu-22.04 ;;
  24.*|25.*|26.*) REPO=ubuntu-24.04 ;;
  *) die "This package targets Ubuntu 22.04 or 24.04 (you have $VERSION_ID)." ;;
esac

KMAJ=${KVER%%.*}; KMIN=${KVER#*.}; KMIN=${KMIN%%.*}
if [ "$KMAJ" -lt 6 ] || { [ "$KMAJ" -eq 6 ] && [ "$KMIN" -lt 6 ]; }; then
  red "Your kernel ($KVER) is too old: the driver needs 6.6 or newer."
  echo "Fix (needs internet, e.g. USB tethering from your phone):"
  echo "   sudo apt update && sudo apt install --install-recommends linux-generic-hwe-22.04"
  echo "   sudo reboot      then run this installer again."
  exit 1
fi

KDIR="/lib/modules/$KVER/build"
if [ ! -e "$KDIR/Makefile" ]; then
  red "Kernel headers are missing ($KDIR)."
  echo "Install them (needs internet, e.g. USB tethering from your phone):"
  echo "   sudo apt update && sudo apt install linux-headers-$KVER"
  exit 1
fi

# 2. Working copy (a FAT32 USB stick is not a good source for apt/dkms) ----
step "Copying files to $WORK"
rm -rf "$WORK"; mkdir -p "$WORK"
cp -r "$SRC_DIR/rtw89" "$WORK/" || die "Could not copy the driver sources."
[ -d "$SRC_DIR/debs" ] && cp -r "$SRC_DIR/debs" "$WORK/"

# 3. Build tools -----------------------------------------------------------
KCC=$(sed -n 's/^CONFIG_CC_VERSION_TEXT="\([^ ]*\) .*/\1/p' "$KDIR/.config" 2>/dev/null)
GCCPKG=""
case "$KCC" in *gcc-[0-9]*) GCCPKG="gcc-${KCC##*gcc-}" ;; esac
echo "Kernel compiler: ${KCC:-unknown}"

NEED=""
for p in build-essential dkms mokutil zstd $GCCPKG; do
  dpkg -s "$p" 2>/dev/null | grep -q '^Status: install ok installed' || NEED="$NEED $p"
done

if [ -z "$NEED" ]; then
  green "Build tools already installed."
elif [ -f "$WORK/debs/$REPO/Packages" ]; then
  step "Installing from the bundled offline repo:$NEED"
  LIST="$WORK/local.list"
  echo "deb [trusted=yes] file:$WORK/debs/$REPO ./" > "$LIST"
  APTOPT=(-o Dir::Etc::SourceList="$LIST" -o Dir::Etc::SourceParts=- -o APT::Get::List-Cleanup=0
          -o APT::Sandbox::User=root)
  apt-get "${APTOPT[@]}" update || die "Could not read the offline repo."
  DEBIAN_FRONTEND=noninteractive apt-get "${APTOPT[@]}" install -y --no-install-recommends $NEED \
    || die "Could not install build tools. If you have internet, try: sudo apt install$NEED"
else
  step "Installing from the internet:$NEED"
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y $NEED \
    || die "Could not install build tools. Connect to the internet or bundle the offline packages (see README)."
fi

# 4. Secure Boot: make sure a signing key exists ---------------------------
SB=no
if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
  SB=yes
  step "Secure Boot is enabled: preparing signing key"
  if [ -d /var/lib/shim-signed ] && [ ! -f /var/lib/shim-signed/mok/MOK.der ] \
     && command -v update-secureboot-policy >/dev/null; then
    update-secureboot-policy --new-key || true
  fi
fi

# 5. Driver via DKMS (rebuilt automatically on kernel updates) -------------
step "Building and installing the driver (takes 2-5 minutes)"
# Remove previous versions
for v in $(dkms status 2>/dev/null | grep -i "^$DRV_NAME[/,]" | sed -E 's#^[^/,]+[/,] *([^,:]+).*#\1#' | sort -u); do
  dkms remove -m "$DRV_NAME" -v "$v" --all >/dev/null 2>&1 || true
done
( cd "$WORK/rtw89" && make cleanup_target_system KVER="$KVER" >/dev/null 2>&1 || true )
rm -rf "/usr/src/$DRV_NAME-$DRV_VER"
cp -r "$WORK/rtw89" "/usr/src/$DRV_NAME-$DRV_VER"
dkms add     -m "$DRV_NAME" -v "$DRV_VER"             || die "dkms add"
dkms build   -m "$DRV_NAME" -v "$DRV_VER" -k "$KVER"  || { tail -40 /var/lib/dkms/$DRV_NAME/$DRV_VER/build/make.log 2>/dev/null; die "Build failed (last lines above)."; }
dkms install -m "$DRV_NAME" -v "$DRV_VER" -k "$KVER"  || die "dkms install"
green "Driver built and installed."

# 6. Firmware and config ---------------------------------------------------
step "Installing firmware and config"
( cd "$WORK/rtw89" && make install_fw ) || die "Could not install the firmware."
cp -v "$WORK/rtw89/rtw89.conf" /etc/modprobe.d/
depmod -a "$KVER"
update-initramfs -u -k "$KVER" >/dev/null 2>&1 || true

# 7. Secure Boot: enroll the key if needed ---------------------------------
REBOOT_MOK=no
if [ "$SB" = yes ]; then
  for KEY in /var/lib/shim-signed/mok/MOK.der /var/lib/dkms/mok.pub; do
    [ -f "$KEY" ] || continue
    if mokutil --test-key "$KEY" 2>&1 | grep -qi 'already enrolled'; then
      echo "Key $KEY is already enrolled."
    else
      step "Enroll Secure Boot key"
      echo "You will be asked for a NEW one-time password (pick something simple, e.g. 12345678)."
      echo "You need it ONCE after rebooting, on a blue screen (MOK Manager):"
      echo "   Enroll MOK  ->  Continue  ->  Yes  ->  type the password  ->  Reboot"
      mokutil --import "$KEY" && REBOOT_MOK=yes
    fi
    break
  done
fi

# 8. Load the driver -------------------------------------------------------
step "Loading the driver"
modprobe -r rtw89_8922au rtw89_8922a rtw89_usb rtw89_core 2>/dev/null || true
if modprobe rtw89_8922au_git 2>&1; then
  sleep 5
  if ip -o link | grep -qE ': wl'; then
    green "Done! Wi-Fi adapter detected:"
    ip -o link | grep -E ': wl' | awk -F': ' '{print "   " $2}'
    echo "Connect to your network from the network icon in the top-right corner."
  else
    echo "The driver loaded but no interface showed up yet. Unplug and replug the adapter."
    echo "If it still does not appear: reboot."
  fi
else
  if [ "$REBOOT_MOK" = yes ]; then
    echo "Expected with Secure Boot: the driver will work after rebooting and enrolling the key."
  else
    echo "Could not load it right now. Reboot the computer."
  fi
fi

[ "$REBOOT_MOK" = yes ] && { echo; red "IMPORTANT: reboot and choose 'Enroll MOK' on the blue screen."; }
echo
green "Installation finished. Log: $LOG"
