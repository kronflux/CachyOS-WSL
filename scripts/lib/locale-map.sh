#!/usr/bin/env bash
# map_windows_locale <culture> -> echoes a Linux locale like "en_US.UTF-8".
# <culture> is a Windows culture name such as "en-US" (from (Get-Culture).Name).
# Falls back to en_US.UTF-8 for empty or malformed input.
map_windows_locale() {
  local culture="${1:-}"
  # Strip CR/LF that PowerShell appends.
  culture="${culture//$'\r'/}"
  culture="${culture//$'\n'/}"

  # Need the "lang-REGION" shape; anything else -> default.
  if [[ "$culture" != *-* ]]; then
    echo "en_US.UTF-8"
    return 0
  fi

  local lang="${culture%%-*}"
  local region="${culture##*-}"
  if [ -z "$lang" ] || [ -z "$region" ]; then
    echo "en_US.UTF-8"
    return 0
  fi

  # Linux uses lang_REGION.UTF-8.
  printf '%s_%s.UTF-8\n' "${lang,,}" "${region^^}"
}
