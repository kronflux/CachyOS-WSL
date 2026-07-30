#!/usr/bin/env bash
# Functional checks against a built rootfs (run in chroot).
# Usage: test-image.sh <TIER>
set -euo pipefail
TIER="${1:-v3}"
WORKDIR="${CACHYWSL_WORKDIR:-/var/tmp/cachywsl}"
BUILDDIR="$WORKDIR/build-$TIER"

[ -d "$BUILDDIR" ] || { echo "no build dir: $BUILDDIR (run build first)"; exit 1; }
run_chroot() { fakechroot -- fakeroot -- chroot "$BUILDDIR" "$@"; }

echo ">>> os-release identifies as CachyOS"
run_chroot grep -q '^ID=cachyos' /usr/lib/os-release

echo ">>> fish is installed and is the configured default shell"
run_chroot test -x /usr/bin/fish
run_chroot test -f /etc/skel/.config/fish/config.fish

echo ">>> cachyos repos are present in pacman.conf"
run_chroot grep -q '\[cachyos' /etc/pacman.conf

echo ">>> wsl.conf enables systemd"
run_chroot grep -q 'systemd=true' /etc/wsl.conf

echo ">>> OOBE and locale-map are present"
run_chroot test -x /usr/lib/wsl/oobe.sh
run_chroot test -f /usr/lib/wsl/locale-map.sh

echo ">>> OOBE user groups exist (so first-boot useradd -G succeeds)"
for g in sys network rfkill users video storage lp audio wheel; do
  run_chroot grep -q "^${g}:" /etc/group
done

echo "ALL FUNCTIONAL TESTS PASSED"
