#!/usr/bin/env bash
# Static validation gate for a built CachyWSL rootfs tree.
# Usage: validate-rootfs.sh <ROOTFS_DIR>   (exit 0 = pass, 1 = fail)
set -uo pipefail

ROOT="${1:-}"
fail=0
err() { echo "FAIL: $*"; fail=1; }
ok()  { echo "PASS: $*"; }

[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "FAIL: rootfs dir not found: '$ROOT'"; exit 1; }

# 1. Required files exist.
for f in etc/wsl.conf etc/wsl-distribution.conf usr/lib/wsl/oobe.sh \
         usr/lib/wsl/terminal-profile.json etc/passwd etc/shadow; do
  if [ -e "$ROOT/$f" ]; then ok "exists: $f"; else err "missing: $f"; fi
done

# 2. wsl.conf content.
grep -q 'systemd=true' "$ROOT/etc/wsl.conf" 2>/dev/null \
  && ok "wsl.conf enables systemd" || err "wsl.conf must set systemd=true"
grep -q 'defaultName = CachyOS' "$ROOT/etc/wsl-distribution.conf" 2>/dev/null \
  && ok "distribution defaultName is CachyOS" || err "wsl-distribution.conf defaultName"

# 3. OOBE executable.
if [ -x "$ROOT/usr/lib/wsl/oobe.sh" ]; then ok "oobe.sh executable"; else err "oobe.sh not executable"; fi

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

[ "$fail" -eq 0 ] && { echo "VALIDATION OK"; exit 0; } || { echo "VALIDATION FAILED"; exit 1; }
