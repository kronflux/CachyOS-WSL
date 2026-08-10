#!/usr/bin/env bash
# Functional checks against the built rootfs (run in chroot).
# Usage: test-image.sh
set -euo pipefail
WORKDIR="${CACHYWSL_WORKDIR:-/var/tmp/cachywsl}"
BUILDDIR="$WORKDIR/build-v3"

[ -d "$BUILDDIR" ] || { echo "no build dir: $BUILDDIR (run build first)"; exit 1; }
run_chroot() { fakechroot -- fakeroot -- chroot "$BUILDDIR" "$@"; }

echo ">>> os-release identifies as CachyOS"
run_chroot grep -q '^ID=cachyos' /usr/lib/os-release

echo ">>> fish is installed and is the configured default shell"
run_chroot test -x /usr/bin/fish
run_chroot test -f /etc/skel/.config/fish/config.fish

echo ">>> done plugin's broken WSL toast is neutralized for new users"
run_chroot grep -q 'functions -e __done_started __done_ended' /etc/skel/.fish_profile

echo ">>> cachyos repos are present in pacman.conf"
run_chroot grep -q '\[cachyos' /etc/pacman.conf

echo ">>> every repo mirrorlist has an active server (pacman -Syu can sync)"
for m in mirrorlist cachyos-mirrorlist cachyos-v3-mirrorlist; do
  run_chroot grep -qE '^[[:space:]]*Server[[:space:]]*=' "/etc/pacman.d/$m" \
    || { echo "FAIL: no active Server in /etc/pacman.d/$m"; exit 1; }
done

echo ">>> zlib-ng-compat replaces stock zlib (CachyOS default)"
run_chroot sh -c 'ls -d /var/lib/pacman/local/zlib-ng-compat-* >/dev/null 2>&1' \
  || { echo "FAIL: zlib-ng-compat not installed"; exit 1; }
run_chroot sh -c '! ls -d /var/lib/pacman/local/zlib-[0-9]* >/dev/null 2>&1' \
  || { echo "FAIL: stock zlib still installed"; exit 1; }

echo ">>> cachy-update CLI present, desktop tray autostart removed"
run_chroot test -x /usr/bin/cachy-update
run_chroot sh -c '[ ! -e /etc/xdg/autostart/arch-update-tray.desktop ]' \
  || { echo "FAIL: cachy-update tray autostart still present"; exit 1; }

echo ">>> wsl.conf enables systemd"
run_chroot grep -q 'systemd=true' /etc/wsl.conf

echo ">>> OOBE and locale-map are present"
run_chroot test -x /usr/lib/wsl/oobe.sh
run_chroot test -f /usr/lib/wsl/locale-map.sh

echo ">>> OOBE user groups exist (so first-boot useradd -G succeeds)"
for g in sys network rfkill users video storage lp audio wheel; do
  run_chroot grep -q "^${g}:" /etc/group
done

echo ">>> cachyos-settings WSL-pointless units still ship upstream AND are masked"
for u in pci-latency.service cachyos-iw-set-regdomain.service cachyos-iw-set-regdomain.path; do
  # Assert the real unit exists (else upstream renamed it -> our mask is stale and
  # the real unit ships un-neutralized). Only then is the /dev/null mask meaningful.
  run_chroot test -e "/usr/lib/systemd/system/$u" \
    || { echo "FAIL: $u no longer shipped by cachyos-settings (renamed?) — mask is stale"; exit 1; }
  [ "$(readlink "$BUILDDIR/etc/systemd/system/$u" 2>/dev/null)" = /dev/null ] \
    || { echo "FAIL: $u not masked"; exit 1; }
done
echo ">>> zram neutralized (no zram-generator config remains)"
run_chroot sh -c '[ ! -e /usr/lib/systemd/zram-generator.conf ] && [ ! -e /etc/systemd/zram-generator.conf ]' \
  || { echo "FAIL: zram-generator config still present"; exit 1; }
echo ">>> cachyos-settings perf tuning retained"
run_chroot test -f /usr/lib/sysctl.d/70-cachyos-settings.conf

echo ">>> OOBE scripts syntax-valid + WSL-parity tools present"
run_chroot test -x /usr/lib/wsl/oobe.sh
run_chroot bash -n /usr/lib/wsl/oobe.sh
run_chroot test -f /usr/lib/wsl/oobe-lib.sh
run_chroot bash -n /usr/lib/wsl/oobe-lib.sh
for b in usr/bin/tmux usr/bin/nc usr/bin/lsof; do
  run_chroot test -e "/$b" || { echo "FAIL: missing /$b"; exit 1; }
done

echo "ALL FUNCTIONAL TESTS PASSED"
