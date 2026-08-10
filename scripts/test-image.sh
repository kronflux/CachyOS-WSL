#!/usr/bin/env bash
# Functional checks against the built rootfs (run in chroot).
# Usage: test-image.sh
set -euo pipefail
WORKDIR="${CACHYWSL_WORKDIR:-/var/tmp/cachywsl}"
BUILDDIR="$WORKDIR/build"

[ -d "$BUILDDIR" ] || { echo "no build dir: $BUILDDIR (run build first)"; exit 1; }
run_chroot() { fakechroot -- fakeroot -- chroot "$BUILDDIR" "$@"; }

echo ">>> os-release identifies as CachyOS"
run_chroot grep -q '^ID=cachyos' /usr/lib/os-release

echo ">>> fish is installed and is the configured default shell"
run_chroot test -x /usr/bin/fish
run_chroot test -f /etc/skel/.config/fish/config.fish

echo ">>> done plugin's broken WSL toast is neutralized for new users"
run_chroot grep -q 'functions -e __done_started __done_ended' /etc/skel/.fish_profile

echo ">>> pacman.conf is generic: [cachyos] enabled, CPU-optimized repos left to first run"
run_chroot grep -qx '\[cachyos\]' /etc/pacman.conf
run_chroot sh -c '! grep -Eq "^\[cachyos-(v3|v4|znver4)\]$" /etc/pacman.conf' \
  || { echo "FAIL: CPU-optimized repos enabled in the shipped image"; exit 1; }
run_chroot test -x /usr/lib/wsl/optimize-repos

echo ">>> no installed package is built for a CPU level above generic x86-64"
if run_chroot sh -c "pacman -Qi | grep -E '^Architecture' | grep -vE ': (x86_64|any)$'"; then
  echo "FAIL: packages above the generic architecture are installed"; exit 1
fi

echo ">>> mirror ranking and pkgfile refresh timers are enabled"
for t in cachyos-rate-mirrors.timer pkgfile-update.timer; do
  [ -L "$BUILDDIR/etc/systemd/system/timers.target.wants/$t" ] || { echo "FAIL: $t not enabled"; exit 1; }
done

echo ">>> every repo mirrorlist has an active server (pacman -Syu can sync)"
for m in mirrorlist cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do
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
run_chroot test -x /usr/lib/wsl/first-setup.sh
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
echo ">>> zram off (the /etc zram-generator config defines no device)"
run_chroot test -f /etc/systemd/zram-generator.conf \
  || { echo "FAIL: /etc/systemd/zram-generator.conf missing"; exit 1; }
run_chroot sh -c '! grep -q "^\[" /etc/systemd/zram-generator.conf' \
  || { echo "FAIL: /etc/systemd/zram-generator.conf defines a zram device"; exit 1; }

echo ">>> wheel sudo rule is installed with mode 0440"
# fakechroot does not wrap statx(), so the mode is read from outside the chroot.
[ "$(stat -c %a "$BUILDDIR/etc/sudoers.d/10-wheel")" = 440 ] \
  || { echo "FAIL: /etc/sudoers.d/10-wheel is not mode 0440"; exit 1; }
echo ">>> cachyos-settings perf tuning retained"
run_chroot test -f /usr/lib/sysctl.d/70-cachyos-settings.conf

echo ">>> OOBE scripts syntax-valid + WSL-parity tools present"
run_chroot test -x /usr/lib/wsl/first-setup.sh
run_chroot bash -n /usr/lib/wsl/first-setup.sh
run_chroot test -f /usr/lib/wsl/oobe-lib.sh
run_chroot bash -n /usr/lib/wsl/oobe-lib.sh
for b in usr/bin/tmux usr/bin/nc usr/bin/lsof; do
  run_chroot test -e "/$b" || { echo "FAIL: missing /$b"; exit 1; }
done

echo "ALL FUNCTIONAL TESTS PASSED"
