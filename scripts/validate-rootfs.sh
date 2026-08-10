#!/usr/bin/env bash
# Static validation gate for a built CachyWSL rootfs tree.
# Usage: validate-rootfs.sh <ROOTFS_DIR>   (exit 0 = pass, 1 = fail)
set -uo pipefail

ROOT="${1:-}"
fail=0
err() { echo "FAIL: $*"; fail=1; }
ok()  { echo "PASS: $*"; }

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "FAIL: rootfs dir not found: '$ROOT'"; exit 1
fi

# 1. Required files exist.
for f in etc/wsl.conf etc/wsl-distribution.conf usr/lib/wsl/first-setup.sh \
         usr/lib/wsl/terminal-profile.json etc/passwd etc/shadow \
         etc/binfmt.d/WSLInterop.conf \
         etc/systemd/system/user@.service.d/50-wsl-retry.conf \
         etc/makepkg.conf; do
  if [ -e "$ROOT/$f" ]; then ok "exists: $f"; else err "missing: $f"; fi
done

# 2. wsl.conf content.
if grep -q 'systemd=true' "$ROOT/etc/wsl.conf" 2>/dev/null; then
  ok "wsl.conf enables systemd"
else
  err "wsl.conf must set systemd=true"
fi
if grep -q 'defaultName = CachyOS' "$ROOT/etc/wsl-distribution.conf" 2>/dev/null; then
  ok "distribution defaultName is CachyOS"
else
  err "wsl-distribution.conf defaultName"
fi

# 3. OOBE and CPU optimizer executable.
if [ -x "$ROOT/usr/lib/wsl/first-setup.sh" ]; then ok "first-setup.sh executable"; else err "first-setup.sh not executable"; fi
if [ -x "$ROOT/usr/lib/wsl/optimize-repos" ]; then ok "optimize-repos executable"; else err "optimize-repos not executable"; fi

# 3b. The image is generic: [cachyos] only, the CPU-optimized repos come at first run.
if grep -qx '\[cachyos\]' "$ROOT/etc/pacman.conf" 2>/dev/null; then
  ok "pacman.conf has [cachyos]"
else
  err "pacman.conf lacks [cachyos]"
fi
if grep -qE '^\[cachyos-(v3|v4|znver4|core-|extra-)' "$ROOT/etc/pacman.conf" 2>/dev/null; then
  err "pacman.conf enables CPU-optimized repos (image must be generic)"
else
  ok "pacman.conf is generic"
fi

# 4. terminal-profile.json is valid JSON.
if jq -e . "$ROOT/usr/lib/wsl/terminal-profile.json" >/dev/null 2>&1; then
  ok "terminal-profile.json is valid JSON"
else
  err "terminal-profile.json is not valid JSON"
fi

# 5. Prohibited files (WSL-managed or build-volatile) must be absent.
for f in etc/resolv.conf etc/machine-id etc/hostname; do
  if [ -e "$ROOT/$f" ]; then err "prohibited file present: $f"; else ok "absent: $f"; fi
done
if compgen -G "$ROOT/boot/vmlinuz*" >/dev/null || compgen -G "$ROOT/boot/initramfs*" >/dev/null; then
  err "kernel/initramfs present (not allowed in WSL)"
else
  ok "no kernel/initramfs"
fi

# 6. shadow must not contain real password hashes for root.
if grep -E '^root:\$' "$ROOT/etc/shadow" >/dev/null 2>&1; then
  err "root has a password hash in /etc/shadow"
else
  ok "root has no password hash"
fi

if [ "$fail" -eq 0 ]; then
  echo "VALIDATION OK"; exit 0
else
  echo "VALIDATION FAILED"; exit 1
fi
