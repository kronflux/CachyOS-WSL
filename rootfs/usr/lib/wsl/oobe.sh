#!/usr/bin/env bash
# CachyWSL out-of-box experience. Runs once on first launch (idempotent).
set -uo pipefail

# shellcheck source=/dev/null
source /usr/lib/wsl/locale-map.sh 2>/dev/null || true

DEFAULT_GROUPS="sys,network,rfkill,users,video,storage,lp,audio,wheel"

echo "Welcome to CachyOS on WSL!"
echo "A CachyOS Linux image for WSL 2 (CachyWSL)."
echo

# --- 1. Locale: detect from Windows, fall back to en_US.UTF-8 -----------------
configure_locale() {
  local culture="" mapped ps
  ps="$(command -v powershell.exe || true)"
  if [ -n "$ps" ]; then
    # WSL's Windows-binary interop (binfmt_misc) may not be registered yet this
    # early in first boot, so powershell.exe can fail with "cannot execute binary
    # file". Retry briefly to let interop come up before falling back to en_US.
    for _ in 1 2 3 4 5; do
      culture="$("$ps" -NoProfile -NonInteractive -Command '(Get-Culture).Name' 2>/dev/null | tr -d '\r\n')"
      [[ "$culture" == *-* ]] && break
      culture=""
      sleep 1
    done
  fi
  [ -n "$culture" ] || culture="en-US"
  if declare -F map_windows_locale >/dev/null; then
    mapped="$(map_windows_locale "$culture")"
  else
    mapped="en_US.UTF-8"
  fi
  echo "Configuring locale: $mapped"
  sed -i "s/^#\\(${mapped} UTF-8\\)/\\1/" /etc/locale.gen 2>/dev/null || true
  locale-gen >/dev/null 2>&1 || true
  echo "LANG=$mapped" > /etc/locale.conf
}

# --- 2. Pacman keyring --------------------------------------------------------
init_keyring() {
  echo "Initializing pacman keyring (one-time)..."
  pacman-key --init >/dev/null 2>&1 || true
  pacman-key --populate archlinux cachyos >/dev/null 2>&1 || true
  echo "Done."
}

# --- 3. Create the default user ----------------------------------------------
create_user() {
  local username=""
  while [ -z "$username" ]; do
    if ! read -r -p "Enter a username for your CachyOS user: " username; then
      echo "No input received (non-interactive); skipping user creation."
      echo "Create one later with: useradd -m -G wheel -s /usr/bin/fish <name> && passwd <name>"
      return 0
    fi
  done
  if ! id -u "$username" >/dev/null 2>&1; then
    # useradd -G is all-or-nothing; keep only groups that actually exist.
    local groups="" g
    for g in ${DEFAULT_GROUPS//,/ }; do
      getent group "$g" >/dev/null 2>&1 && groups="${groups:+$groups,}$g"
    done
    useradd --create-home --uid 1000 ${groups:+--groups "$groups"} \
            --shell /usr/bin/fish "$username"
    echo "Set a password for $username:"
    passwd "$username"
  fi
  # Make this the default WSL user.
  if ! grep -q '^\[user\]' /etc/wsl.conf 2>/dev/null; then
    printf '\n[user]\ndefault=%s\n' "$username" >> /etc/wsl.conf
  fi
}

configure_locale
init_keyring
create_user

echo
echo "CachyOS is ready. It is strongly recommended to run 'sudo pacman -Syu' now."
