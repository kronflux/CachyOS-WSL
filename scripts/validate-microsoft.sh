#!/usr/bin/env bash
# Run Microsoft's WSL image validator (microsoft/WSL distributions/validate-modern.py)
# against a built .wsl image.
# Usage: validate-microsoft.sh <image.wsl>
set -euo pipefail
# pip installs the validator's requirements without a download cache and
# without checking for a newer pip.
export PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

IMAGE="${1:?usage: validate-microsoft.sh <image.wsl>}"
[ -f "$IMAGE" ] || { echo "error: image not found: $IMAGE" >&2; exit 1; }
IMAGE="$(realpath "$IMAGE")"

WORKDIR="${CACHYWSL_WORKDIR:-/var/tmp/cachywsl}"
CLONEDIR="$WORKDIR/microsoft-wsl"
VENVDIR="$WORKDIR/microsoft-wsl-venv"

if [ -d "$CLONEDIR/.git" ]; then
  git -C "$CLONEDIR" pull --quiet --ff-only
else
  git clone --quiet --depth 1 https://github.com/microsoft/WSL.git "$CLONEDIR"
fi
[ -x "$VENVDIR/bin/python" ] || python -m venv "$VENVDIR"
"$VENVDIR/bin/pip" install --quiet -r "$CLONEDIR/distributions/requirements.txt"
"$VENVDIR/bin/python" "$CLONEDIR/distributions/validate-modern.py" --tar "$IMAGE"
