#!/bin/bash
# Removes the driver installed by install.sh.   Usage:  sudo bash uninstall.sh
[ "$(id -u)" -eq 0 ] || { echo "Run:  sudo bash $0"; exit 1; }
for v in $(dkms status 2>/dev/null | grep -i '^rtw89[/,]' | sed -E 's#^[^/,]+[/,] *([^,:]+).*#\1#' | sort -u); do
  dkms remove -m rtw89 -v "$v" --all
done
rm -rf /usr/src/rtw89-*
rm -f /etc/modprobe.d/rtw89.conf
depmod -a
update-initramfs -u >/dev/null 2>&1 || true
echo "Driver removed. Reboot the computer."
