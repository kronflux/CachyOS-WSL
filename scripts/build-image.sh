#!/usr/bin/env bash
# Build a CachyWSL rootfs image for a CPU tier.
# Usage: build-image.sh <v3|v4|znver4> <IMAGE_VERSION>
set -euo pipefail
export TZ=UTC

TIER="${1:?usage: build-image.sh <tier> <image_version>}"
IMAGE_VERSION="${2:?usage: build-image.sh <tier> <image_version>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKDIR="$ROOT_DIR/workdir"
BUILDDIR="$WORKDIR/build-$TIER"
OUTPUTDIR="$ROOT_DIR/output"

SOURCE_DATE_EPOCH="$(date -u -d "$(awk -F. '{print $1"-"$2"-"$3}' <<<"$IMAGE_VERSION")" +%s 2>/dev/null || date -u +%s)"
export SOURCE_DATE_EPOCH

echo ">>> Building CachyWSL tier=$TIER version=$IMAGE_VERSION (SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH)"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR" "$OUTPUTDIR"

# --- 1. Build pacman.conf: base + CachyOS repos for the tier.
#     GPGDir reuses the HOST keyring (already trusts archlinux+cachyos keys) so
#     packages verify against the fresh, empty target keyring.
BUILD_PACMAN_CONF="$WORKDIR/pacman-$TIER.conf"
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
"$SCRIPT_DIR/inject-cachyos-repos.sh" "$TIER" "$BUILD_PACMAN_CONF"
# Point the injected [cachyos*] Include paths at our vendored, self-contained
# mirrorlists (host may not carry every tier's mirrorlist).
sed -i "s#/etc/pacman.d/cachyos-#$ROOT_DIR/vendor/mirrorlists/cachyos-#g" "$BUILD_PACMAN_CONF"

# --- 2. Neutralize ALPM hooks during bootstrap (target-absolute path prefixed).
mkdir -p "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks"
find /usr/share/libalpm/hooks -maxdepth 1 -type f -exec \
  ln -sf /dev/null "$BUILDDIR/alpm-hooks"{} \; 2>/dev/null || true

# --- 3. Install packages into the rootfs (rootless).
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$ROOT_DIR/packages/base.list")
echo ">>> Installing ${#PKGS[@]} packages..."
fakechroot -- fakeroot -- pacman -Sy -r "$BUILDDIR" \
  --config "$BUILD_PACMAN_CONF" \
  --disable-sandbox-filesystem \
  --noconfirm --noscriptlet \
  --hookdir "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks/" \
  "${PKGS[@]}"

# --- 4. Overlay rootfs/ and wire os-release.
cp --recursive --preserve=timestamps "$ROOT_DIR/rootfs/." "$BUILDDIR/"
install -Dm0755 "$SCRIPT_DIR/lib/locale-map.sh" "$BUILDDIR/usr/lib/wsl/locale-map.sh"
install -Dm0644 "$ROOT_DIR/rootfs/usr/lib/wsl/hooks/50-setcap-iputils.hook" \
  "$BUILDDIR/etc/pacman.d/hooks/50-setcap-iputils.hook"
ln -sf /usr/lib/os-release "$BUILDDIR/etc/os-release"

# --- 5. Post-install system configuration (chroot).
run_chroot() { fakechroot -- fakeroot -- chroot "$BUILDDIR" "$@"; }
run_chroot /usr/bin/update-ca-trust || true
run_chroot /usr/bin/systemd-sysusers || true
run_chroot /usr/share/libalpm/scripts/cachyos-branding || true
# Tier-appropriate makepkg.conf (fall back to v3 preset if the tier preset is absent).
case "$TIER" in
  v3)        MPCONF="$ROOT_DIR/vendor/makepkg/x86_64_v3.conf" ;;
  v4|znver4) MPCONF="$ROOT_DIR/vendor/makepkg/x86_64_v4.conf"
             [ -f "$MPCONF" ] || MPCONF="$ROOT_DIR/vendor/makepkg/x86_64_v3.conf" ;;
  *)         MPCONF="$ROOT_DIR/vendor/makepkg/x86_64_v3.conf" ;;
esac
install -Dm0644 "$MPCONF" "$BUILDDIR/etc/makepkg.conf"
# Enable Color + ILoveCandy in the shipped pacman.conf.
if [ -f "$BUILDDIR/etc/pacman.conf" ]; then
  sed -i -e 's/^#\?Color$/Color/' "$BUILDDIR/etc/pacman.conf"
  grep -q '^ILoveCandy' "$BUILDDIR/etc/pacman.conf" || \
    sed -i '/^Color$/a ILoveCandy' "$BUILDDIR/etc/pacman.conf"
fi
# Wheel sudo (password required).
install -d -m0750 "$BUILDDIR/etc/sudoers.d"
echo '%wheel ALL=(ALL:ALL) ALL' > "$BUILDDIR/etc/sudoers.d/10-wheel"
chmod 0440 "$BUILDDIR/etc/sudoers.d/10-wheel"

# --- 6. WSL hardening: mask conflicting units, drop WSL-irrelevant hooks.
for unit in systemd-firstboot console-getty getty@ serial-getty@ \
            systemd-resolved systemd-networkd NetworkManager \
            systemd-tmpfiles-setup systemd-tmpfiles-clean.timer tmp.mount; do
  ln -sf /dev/null "$BUILDDIR/etc/systemd/system/${unit}.service" 2>/dev/null || true
done
ln -sf /dev/null "$BUILDDIR/etc/systemd/system/getty.target" 2>/dev/null || true
rm -f "$BUILDDIR/usr/share/libalpm/hooks/cachyos-plymouth-initramfs.hook" \
      "$BUILDDIR/usr/share/libalpm/hooks/cachyos-reboot-required.hook" 2>/dev/null || true

# --- 7. Cleanup for reproducible packaging.
rm -rf "$BUILDDIR"/etc/pacman.d/gnupg/* 2>/dev/null || true
find "$BUILDDIR" -exec touch --no-dereference --date="@$SOURCE_DATE_EPOCH" {} + 2>/dev/null || true

# --- 8. Pack deterministically -> .wsl.
OUT="$OUTPUTDIR/cachyos-$TIER-$IMAGE_VERSION"
fakeroot -- tar \
  --numeric-owner --xattrs --acls \
  --mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime --sort=name \
  --pax-option=delete=atime,delete=ctime \
  --exclude-from="$SCRIPT_DIR/exclude" \
  -C "$BUILDDIR" -c . -f "$OUT.tar"
xz -9 -T0 -f "$OUT.tar"
mv "$OUT.tar.xz" "$OUT.wsl"
( cd "$OUTPUTDIR" && sha256sum "$(basename "$OUT.wsl")" > "$(basename "$OUT.wsl").sha256" )

echo ">>> Built $OUT.wsl"
ls -lh "$OUT.wsl" "$OUT.wsl.sha256"
