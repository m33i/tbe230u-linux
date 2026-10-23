# TP-Link Archer TBE230U on Linux

TP-Link only ships Windows drivers for the **Archer TBE230U** (BE3600 Wi-Fi 7 USB adapter).
This repo makes it work on **Ubuntu 24.04** (also meant for 22.04) with a one-command installer
that works **offline**, so you can set it up on a PC whose only network is the adapter itself.

## What's inside

- `rtw89/`: the community [morrownr/rtw89](https://github.com/morrownr/rtw89) driver for the adapter's
  Realtek RTL8912AU chip, plus firmware. Changes from upstream:
  - adds USB ID `37ad:0105` (some TBE230U units use it, and neither upstream nor the mainline kernel lists it)
  - builds with the same gcc version the kernel was built with (needed for Ubuntu HWE kernels)
- `install.sh`: installs the build tools, then builds the driver with DKMS (so it rebuilds itself on kernel
  updates), installs the firmware, handles Secure Boot key enrollment and loads the driver
- `uninstall.sh`: removes everything
- `scripts/fetch-debs.sh`: downloads the build tools into `debs/` as local apt repos, for offline installs

## Requirements

- Ubuntu 24.04 (tested on 24.04.3, kernels 6.14 and 6.17) or 22.04 with an HWE kernel (not tested)
- Linux kernel 6.6 or newer
- Kernel headers installed (Ubuntu desktop installs them by default)
- Check your adapter's ID with `lsusb`. It should show `37ad:0104` or `37ad:0105`

## Usage

**Offline (easiest):** download `tbe230u-linux-ubuntu24.04.zip` from the
[latest release](../../releases/latest) on any computer and unzip it onto a USB stick. On the Ubuntu machine:

```bash
cd /media/$USER/<usb-name>/tbe230u-linux
sudo bash install.sh
```

**With internet:** clone the repo and run `sudo bash install.sh`. Without the `debs/` folder, the installer
downloads the build tools itself. If the adapter is your only network, USB tethering from a phone works
on Ubuntu without extra drivers.

**Rebuild the offline packages** (needs Docker): `bash scripts/fetch-debs.sh`

If Secure Boot is enabled, the installer asks you to choose a one-time password. Reboot, then in the blue
MOK Manager screen choose **Enroll MOK → Continue → Yes**, type that password and reboot.

## Notes

- Mainline Linux supports the RTL8912AU from kernel 7.1, and the TP-Link ID `37ad:0104` from 7.4.
  On those kernels this repo isn't needed.
- MLO (Wi-Fi 7 multi-link) is not expected to work on Linux.

## License

The driver is GPL-2.0 / BSD-3-Clause (see `rtw89/`). The firmware is under the license in `rtw89/firmware/`.
