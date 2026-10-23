#!/bin/bash
# Builds the offline apt repos in debs/ (build-essential, dkms, ...) for Ubuntu 22.04 and 24.04.
# Needs Docker. Run from the repo root:  bash scripts/fetch-debs.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

INNER='
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends dpkg-dev >/dev/null
LIST=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
        --no-breaks --no-replaces --no-enhances $PKGS | grep "^[a-z0-9]" | sort -u)
cd /out
for p in $LIST; do
  apt-cache show "$p" >/dev/null 2>&1 || continue   # skip virtual packages
  apt-get download -qq "$p" 2>/dev/null || echo "WARN: could not download $p"
done
rm -f Packages Packages.gz
dpkg-scanpackages -m . /dev/null 2>/dev/null > Packages
gzip -9k Packages
echo "OK: $(ls *.deb | wc -l) packages, $(du -sh . | cut -f1)"
'

BASE="build-essential dkms mokutil zstd usb-modeswitch usb-modeswitch-data kmod"
# Ubuntu 22.04 HWE kernels are built with gcc-12; 24.04 kernels use gcc-13 (build-essential default)
for spec in "22.04:gcc-12" "24.04:"; do
  rel=${spec%%:*}; extra=${spec#*:}
  out="$ROOT/debs/ubuntu-$rel"
  rm -rf "$out"; mkdir -p "$out"
  echo "==> Ubuntu $rel"
  docker run --rm --platform linux/amd64 -e PKGS="$BASE $extra" -v "$out":/out \
    "ubuntu:$rel" bash -c "$INNER"
done
