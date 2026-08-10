#!/usr/bin/env bash
# Inject the CachyOS x86-64-v3 optimized repositories into a pacman.conf.
# Usage: inject-cachyos-repos.sh <path/to/pacman.conf>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/../vendor/cachyos-repo"

conf="${1:-}"
if [ -z "$conf" ] || [ ! -f "$conf" ]; then
  echo "error: pacman.conf not found: '$conf'" >&2
  exit 2
fi

gawk -i inplace -f "$VENDOR_DIR/install-repo.awk" "$conf"
