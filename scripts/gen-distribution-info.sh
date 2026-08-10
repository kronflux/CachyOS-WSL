#!/usr/bin/env bash
# Emit a WSL DistributionInfo.json for the built .wsl images in <dir>.
# Usage: gen-distribution-info.sh <tag> <dir>
set -euo pipefail
TAG="${1:?usage: gen-distribution-info.sh <tag> <dir>}"
DIR="${2:?usage: gen-distribution-info.sh <tag> <dir>}"
SLUG="kronflux/CachyOS-WSL"

json='{"ModernDistributions":{"CachyOS":[]}}'
add_tier() {
  local tier="$1" name="$2" friendly="$3" default="$4"
  local sha file
  local matches=("$DIR"/cachyos-"$tier"-*.wsl)
  local wsl="${matches[0]}"
  [ -e "$wsl" ] || return 0   # no match: glob stayed literal
  file="$(basename "$wsl")"
  sha="$(awk '{print $1}' "$wsl.sha256")"
  json="$(jq \
    --arg Name "$name" --arg FriendlyName "$friendly" --argjson Default "$default" \
    --arg Url "https://github.com/$SLUG/releases/download/$TAG/$file" \
    --arg Sha256 "$sha" \
    '.ModernDistributions.CachyOS += [{"Name":$Name,"FriendlyName":$FriendlyName,"Default":$Default,"Amd64Url":{"Url":$Url,"Sha256":$Sha256}}]' \
    <<<"$json")"
}
add_tier v3 CachyOS "CachyOS (x86-64-v3)" true
jq . <<<"$json"
