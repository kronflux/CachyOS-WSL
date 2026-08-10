#!/usr/bin/env bash
# Pure, sourceable helpers for the CachyWSL OOBE. Sourcing has no side effects.

# validate_username <name>: exit 0 if a valid Linux/WSL username, 1 otherwise.
validate_username() {
  local name="${1:-}"
  case "$name" in root|daemon|bin|sys|nobody) return 1 ;; esac
  [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

# oobe_conf_get <file> <key> [default]: echo value of key= (comment/blank tolerant,
# quote/space stripped) or default.
oobe_conf_get() {
  local file="$1" key="$2" default="${3:-}" line val
  [ -f "$file" ] || { printf '%s' "$default"; return 0; }
  line="$(grep -vE '^[[:space:]]*#' "$file" 2>/dev/null | grep -E "^[[:space:]]*${key}[[:space:]]*=" | tail -1)"
  [ -n "$line" ] || { printf '%s' "$default"; return 0; }
  val="${line#*=}"
  val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/')"
  printf '%s' "$val"
}

# oobe_bool <value>: echo "yes" for yes/y/true/1 (case-insensitive), else "no".
oobe_bool() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    yes|y|true|1) printf 'yes' ;; *) printf 'no' ;;
  esac
}
