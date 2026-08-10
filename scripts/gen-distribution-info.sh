#!/usr/bin/env bash
# Emit a WSL DistributionInfo.json for the built .wsl image in <dir>.
# Usage: gen-distribution-info.sh <tag> <dir>
set -euo pipefail
TAG="${1:?usage: gen-distribution-info.sh <tag> <dir>}"
DIR="${2:?usage: gen-distribution-info.sh <tag> <dir>}"
SLUG="kronflux/CachyOS-WSL"

json='{"ModernDistributions":{"CachyOS":[]}}'
wsl="$DIR/cachyos-$TAG.wsl"
if [ -e "$wsl" ]; then
  file="$(basename "$wsl")"
  sha="$(awk '{print $1}' "$wsl.sha256")"
  json="$(jq \
    --arg Url "https://github.com/$SLUG/releases/download/$TAG/$file" \
    --arg Sha256 "$sha" \
    '.ModernDistributions.CachyOS += [{"Name":"CachyOS","FriendlyName":"CachyOS","Default":true,"Amd64Url":{"Url":$Url,"Sha256":$Sha256}}]' \
    <<<"$json")"
fi
jq . <<<"$json"
