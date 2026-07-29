#!/usr/bin/env bash
# Inject CachyOS optimized repos into a pacman.conf for a given CPU tier.
# Usage: inject-cachyos-repos.sh <v3|v4|znver4> <path/to/pacman.conf>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/../vendor/cachyos-repo"

tier="${1:-}"
conf="${2:-}"

case "$tier" in
  v3)     awk_file="install-repo.awk" ;;
  v4)     awk_file="install-v4-repo.awk" ;;
  znver4) awk_file="install-znver4-repo.awk" ;;
  *) echo "error: unknown tier '$tier' (expected v3|v4|znver4)" >&2; exit 2 ;;
esac

if [ -z "$conf" ] || [ ! -f "$conf" ]; then
  echo "error: pacman.conf not found: '$conf'" >&2
  exit 2
fi

gawk -i inplace -f "$VENDOR_DIR/$awk_file" "$conf"
