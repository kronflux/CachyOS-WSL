#!/usr/bin/env bash
# Build the CachyWSL x86-64-v3 rootfs image.
# Usage: build-image.sh <IMAGE_VERSION>
set -euo pipefail
export TZ=UTC

IMAGE_VERSION="${1:?usage: build-image.sh <image_version>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Build on a NATIVE filesystem. /mnt/c (DrvFs/9p) cannot store Unix mode or
# setuid bits, so building there produces a 0777, no-setuid (broken sudo,
# world-writable) image. Override with CACHYWSL_WORKDIR if /var/tmp is unsuitable.
WORKDIR="${CACHYWSL_WORKDIR:-/var/tmp/cachywsl}"
BUILDDIR="$WORKDIR/build-v3"
OUTPUTDIR="$ROOT_DIR/output"

SOURCE_DATE_EPOCH="$(date -u -d "$(awk -F. '{print $1"-"$2"-"$3}' <<<"$IMAGE_VERSION")" +%s 2>/dev/null || date -u +%s)"
export SOURCE_DATE_EPOCH

echo ">>> Building CachyWSL version=$IMAGE_VERSION (SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH)"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR" "$OUTPUTDIR"
# pacman -r into an empty root needs these to exist (pacstrap normally makes them).
mkdir -p "$BUILDDIR/var/lib/pacman" "$BUILDDIR/var/cache/pacman/pkg"
# Fresh per-build package cache inside the (wiped-each-build) BUILDDIR — isolated
# from the HOST cache. A corrupted package cached from the host or a prior build
# would otherwise fail signature verification and abort (pacman does not retry
# another mirror on a bad signature).
PKGCACHE="$BUILDDIR/var/cache/pacman/pkg"

# --- 1. Build pacman.conf: base + CachyOS v3 repos.
#     GPGDir reuses the HOST keyring (already trusts archlinux+cachyos keys) so
#     packages verify against the fresh, empty target keyring.
BUILD_PACMAN_CONF="$WORKDIR/pacman-v3.conf"
cat > "$BUILD_PACMAN_CONF" <<'EOF'
[options]
Architecture = x86_64
GPGDir = /etc/pacman.d/gnupg
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF
"$SCRIPT_DIR/inject-cachyos-repos.sh" "$BUILD_PACMAN_CONF"
# Point the injected [cachyos*] Include paths at our vendored, self-contained
# mirrorlists (the build host may not carry them).
sed -i "s#/etc/pacman.d/cachyos-#$ROOT_DIR/vendor/mirrorlists/cachyos-#g" "$BUILD_PACMAN_CONF"
# The injected `Architecture = auto` would detect the builder's own CPU; pin it to
# the x86-64-v3 packages the image ships so any builder accepts them.
sed -i 's/^Architecture = .*/Architecture = x86_64 x86_64_v3/' "$BUILD_PACMAN_CONF"

# --- 2. Neutralize ALPM hooks during bootstrap (target-absolute path prefixed).
mkdir -p "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks"
find /usr/share/libalpm/hooks -maxdepth 1 -type f -exec \
  ln -sf /dev/null "$BUILDDIR/alpm-hooks"{} \; 2>/dev/null || true

# --- 3. Install packages into the rootfs (rootless).
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$ROOT_DIR/packages/base.list")
echo ">>> Installing ${#PKGS[@]} packages..."
fakechroot -- fakeroot -- pacman -Sy -r "$BUILDDIR" \
  --config "$BUILD_PACMAN_CONF" \
  --cachedir "$PKGCACHE" \
  --disable-sandbox-filesystem \
  --noconfirm --noscriptlet \
  --hookdir "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks/" \
  "${PKGS[@]}"

# Sanity guard: fakechroot/fakeroot can mask a non-zero pacman exit, so verify a
# few critical files landed rather than trusting the exit code.
for crit in usr/lib/libc.so.6 usr/bin/bash usr/bin/pacman usr/bin/fish usr/bin/sudo; do
  [ -e "$BUILDDIR/$crit" ] || { echo "error: missing critical file '$crit' — package install incomplete" >&2; exit 1; }
done

# CachyOS ships zlib-ng-compat in place of stock zlib (it Provides + Replaces zlib).
# The `base` group pulls concrete zlib, so swap it in a second transaction — the
# same result as the CachyOS installer, without a runtime replace prompt.
echo ">>> Swapping zlib -> zlib-ng-compat"
# Under --noconfirm pacman answers the "Remove zlib?" conflict prompt with its
# default (No), so drop stock zlib explicitly first; zlib-ng-compat Provides the
# zlib ABI, so dependents keep working once it is installed.
fakechroot -- fakeroot -- pacman -Rdd -r "$BUILDDIR" \
  --config "$BUILD_PACMAN_CONF" --noconfirm --noscriptlet \
  --hookdir "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks/" zlib
fakechroot -- fakeroot -- pacman -S -r "$BUILDDIR" \
  --config "$BUILD_PACMAN_CONF" \
  --cachedir "$PKGCACHE" \
  --disable-sandbox-filesystem \
  --noconfirm --noscriptlet \
  --hookdir "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks/" \
  zlib-ng-compat
compgen -G "$BUILDDIR/var/lib/pacman/local/zlib-ng-compat-*" >/dev/null \
  || { echo "error: zlib-ng-compat swap failed" >&2; exit 1; }
if compgen -G "$BUILDDIR/var/lib/pacman/local/zlib-[0-9]*" >/dev/null; then
  echo "error: stock zlib still installed after swap" >&2; exit 1
fi

# --- 4. Overlay rootfs/ and wire os-release.
cp --recursive --preserve=timestamps "$ROOT_DIR/rootfs/." "$BUILDDIR/"
install -Dm0755 "$SCRIPT_DIR/lib/locale-map.sh" "$BUILDDIR/usr/lib/wsl/locale-map.sh"
install -Dm0644 "$SCRIPT_DIR/lib/oobe-lib.sh" "$BUILDDIR/usr/lib/wsl/oobe-lib.sh"
install -Dm0644 "$ROOT_DIR/rootfs/usr/lib/wsl/hooks/50-setcap-iputils.hook" \
  "$BUILDDIR/etc/pacman.d/hooks/50-setcap-iputils.hook"
ln -sf /usr/lib/os-release "$BUILDDIR/etc/os-release"

# --- 5. Post-install system configuration (chroot).
run_chroot() { fakechroot -- fakeroot -- chroot "$BUILDDIR" "$@"; }
run_chroot /usr/bin/update-ca-trust || true
run_chroot /usr/bin/systemd-sysusers || true
# systemd-sysusers creates the system groups the OOBE user is added to. Assert a
# representative one so a swallowed failure can't ship an image where user
# creation (useradd -G) would fail at first boot.
grep -q '^wheel:' "$BUILDDIR/etc/group" || \
  { echo "error: system groups missing (systemd-sysusers failed)" >&2; exit 1; }
# Grant non-root ping now (the pacman hook only re-applies on future ping upgrades).
run_chroot /usr/bin/setcap cap_net_raw+p /usr/bin/ping 2>/dev/null || true
# CachyOS branding: the upstream script seds /etc/os-release (breaking our symlink
# into a regular file). Run it, then promote the branded content to the canonical
# /usr/lib/os-release and restore /etc/os-release as a symlink so both agree.
run_chroot /usr/share/libalpm/scripts/cachyos-branding os-release || true
if [ -f "$BUILDDIR/etc/os-release" ] && [ ! -L "$BUILDDIR/etc/os-release" ]; then
  cp "$BUILDDIR/etc/os-release" "$BUILDDIR/usr/lib/os-release"
  ln -sf /usr/lib/os-release "$BUILDDIR/etc/os-release"
fi
grep -q '^ID=cachyos' "$BUILDDIR/usr/lib/os-release" || \
  { echo "error: os-release branding failed (ID not cachyos)" >&2; exit 1; }
# x86-64-v3 makepkg preset so in-image rebuilds target the same arch.
install -Dm0644 "$ROOT_DIR/vendor/makepkg/x86_64_v3.conf" "$BUILDDIR/etc/makepkg.conf"
# Inject CachyOS repos into the SHIPPED /etc/pacman.conf so `pacman -Syu` uses
# them at runtime. No vendor-repoint here: the image already ships
# /etc/pacman.d/cachyos-*-mirrorlist from the installed mirrorlist packages.
if [ -f "$BUILDDIR/etc/pacman.conf" ]; then
  "$SCRIPT_DIR/inject-cachyos-repos.sh" "$BUILDDIR/etc/pacman.conf"
  grep -q '^\[cachyos' "$BUILDDIR/etc/pacman.conf" || \
    { echo "error: failed to inject CachyOS repos into shipped pacman.conf" >&2; exit 1; }
fi
# Enable Color + ILoveCandy in the shipped pacman.conf.
if [ -f "$BUILDDIR/etc/pacman.conf" ]; then
  sed -i -e 's/^#\?Color$/Color/' "$BUILDDIR/etc/pacman.conf"
  grep -q '^ILoveCandy' "$BUILDDIR/etc/pacman.conf" || \
    sed -i '/^Color$/a ILoveCandy' "$BUILDDIR/etc/pacman.conf"
fi
# Arch [core]/[extra] Include /etc/pacman.d/mirrorlist, which the pacman-mirrorlist
# package ships with every Server commented out (so `pacman -Syu` would fail with
# "no servers configured"). Point it at Arch's official worldwide geo-redirecting
# mirror, which resolves to a nearby mirror for any user.
cat > "$BUILDDIR/etc/pacman.d/mirrorlist" <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
EOF
# Wheel sudo (password required).
install -d -m0750 "$BUILDDIR/etc/sudoers.d"
echo '%wheel ALL=(ALL:ALL) ALL' > "$BUILDDIR/etc/sudoers.d/10-wheel"
chmod 0440 "$BUILDDIR/etc/sudoers.d/10-wheel"
# Pre-generate a default UTF-8 locale so the image is warning-free even when OOBE
# (which detects the Windows locale) does not run, e.g. under `wsl --import`.
# locale-gen's archive build fails under fakechroot; --no-archive writes a plain
# per-locale directory that glibc reads directly.
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$BUILDDIR/etc/locale.gen"
run_chroot /usr/bin/localedef --no-archive -i en_US -f UTF-8 en_US.UTF-8 || true
fakechroot -- fakeroot -- chroot "$BUILDDIR" /usr/bin/locale -a 2>/dev/null | grep -qi '^en_US.utf8$' || \
  { echo "error: en_US.UTF-8 locale not generated" >&2; exit 1; }

# --- 6. WSL hardening: mask conflicting units, drop WSL-irrelevant hooks.
# Match the official Arch WSL set: only the getty/firstboot units (Hyper-V
# shared-TTY fix, WSL#13595). Do NOT mask tmpfiles/tmp.mount/networkd/resolved —
# masking systemd-tmpfiles-setup/tmp.mount breaks /run/user creation and the
# systemd user session on first boot.
for unit in systemd-firstboot console-getty; do
  ln -sf /dev/null "$BUILDDIR/etc/systemd/system/${unit}.service" 2>/dev/null || true
done
for unit in getty@.service serial-getty@.service getty.target; do
  ln -sf /dev/null "$BUILDDIR/etc/systemd/system/${unit}" 2>/dev/null || true
done
# --- cachyos-settings audit: neutralize WSL-pointless units it ships.
#   zram        -> WSL manages its own swap; no zram device wanted
#   pci-latency -> no PCI bus in WSL
#   iw-regdomain-> no wireless in WSL
for unit in pci-latency.service cachyos-iw-set-regdomain.service cachyos-iw-set-regdomain.path; do
  ln -sf /dev/null "$BUILDDIR/etc/systemd/system/${unit}" 2>/dev/null || true
done
rm -f "$BUILDDIR/usr/lib/systemd/zram-generator.conf" \
      "$BUILDDIR/etc/systemd/zram-generator.conf" 2>/dev/null || true
ln -sf /dev/null "$BUILDDIR/etc/systemd/system/systemd-zram-setup@zram0.service" 2>/dev/null || true
# Keep the perf tuning: 70-cachyos-settings.conf (sysctl), thp*.conf (tmpfiles),
# systemd limits/timeouts, journald size — all harmless or beneficial in WSL.
rm -f "$BUILDDIR/usr/share/libalpm/hooks/cachyos-plymouth-initramfs.hook" \
      "$BUILDDIR/usr/share/libalpm/hooks/cachyos-reboot-required.hook" 2>/dev/null || true
# cachy-update ships a desktop systray applet + update-check timer; keep only the
# CLI (arch-update) by dropping the tray autostart and masking the user timer.
rm -f "$BUILDDIR/etc/xdg/autostart/arch-update-tray.desktop" 2>/dev/null || true
install -d "$BUILDDIR/etc/systemd/user"
ln -sf /dev/null "$BUILDDIR/etc/systemd/user/arch-update.timer" 2>/dev/null || true

# --- 7. Cleanup for reproducible packaging.
rm -rf "$BUILDDIR"/etc/pacman.d/gnupg/* 2>/dev/null || true
find "$BUILDDIR" -exec touch --no-dereference --date="@$SOURCE_DATE_EPOCH" {} + 2>/dev/null || true

# --- 8. Pack deterministically -> .wsl.
OUT="$OUTPUTDIR/cachyos-v3-$IMAGE_VERSION"
fakeroot -- tar \
  --numeric-owner --xattrs --acls \
  --mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime --sort=name \
  --pax-option=delete=atime,delete=ctime \
  --exclude-from="$SCRIPT_DIR/exclude" \
  -C "$BUILDDIR" -c . -f "$OUT.tar"
# Single-threaded xz for cross-host deterministic output (-T0 varies with core count).
xz -9 -T1 -f "$OUT.tar"
mv "$OUT.tar.xz" "$OUT.wsl"
( cd "$OUTPUTDIR" && sha256sum "$(basename "$OUT.wsl")" > "$(basename "$OUT.wsl").sha256" )

echo ">>> Built $OUT.wsl"
ls -lh "$OUT.wsl" "$OUT.wsl.sha256"
