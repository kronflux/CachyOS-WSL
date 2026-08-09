#!/usr/bin/env bash
# Verify vendored text assets against vendor/SHA256SUMS.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../vendor"
sha256sum --quiet -c SHA256SUMS
echo "vendored assets verified"
