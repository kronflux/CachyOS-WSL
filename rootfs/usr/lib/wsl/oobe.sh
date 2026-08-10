#!/usr/bin/env bash
# CachyWSL out-of-box experience. Runs once on first launch (idempotent).
# MUST exit 0 on recoverable failures: a non-zero exit locks the user out of the shell.
set -uo pipefail

# Ctrl-C / SIGTERM must not leave a non-zero exit — WSL would lock the user out of
# the shell. Exit cleanly on signal (they can finish setup from the root shell).
trap 'exit 0' INT TERM

# Count code points (not bytes) so the padded columns line up, independent of the
# locale being configured below. C.UTF-8 is built into glibc.
locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$' && export LC_ALL=C.UTF-8

# shellcheck source=/dev/null
source /usr/lib/wsl/oobe-lib.sh 2>/dev/null || true
# shellcheck source=/dev/null
source /usr/lib/wsl/locale-map.sh 2>/dev/null || true
command -v validate_username >/dev/null 2>&1 || validate_username() {
  case "${1:-}" in root|daemon|bin|sys|nobody) return 1 ;; esac
  [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

OOBE_CONF=/etc/wsl/oobe.conf
DEFAULT_GROUPS="sys,network,rfkill,users,video,storage,lp,audio,wheel"
UPDATE_LOG=/var/log/cachywsl-firstboot.log
LBLW=25   # step label column width ("Update System Packages" is 22)
VALW=20   # step value column width, aligns the check / spinner

# --- palette (degrade on non-tty / NO_COLOR) ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  TEAL=$'\e[38;5;44m'; BTEAL=$'\e[1;38;5;44m'
  GN=$'\e[38;5;42m';   DM=$'\e[38;5;242m'; RS=$'\e[0m'
  TTY=yes; CR=$'\r'
else
  TEAL=""; BTEAL=""; GN=""; DM=""; RS=""; TTY=no; CR=""
fi
CHK=$'\xe2\x9c\x93'   # heavy check
PND=$'\xe2\x97\x8b'   # ring (pending / skipped / failed)
ARR=$'\xe2\x80\xba'   # single angle quote (prompts)
RARR=$'\xe2\x86\x92'  # rightwards arrow (label -> value)
ELL=$'\xe2\x80\xa6'   # ellipsis
ELB=$'\xe2\x94\x94'   # box-drawing up-and-right
BH=$'\xe2\x94\x80'; BV=$'\xe2\x94\x82'           # box horizontal / vertical
BTL=$'\xe2\x95\xad'; BTR=$'\xe2\x95\xae'          # box top corners
BBL=$'\xe2\x95\xb0'; BBR=$'\xe2\x95\xaf'          # box bottom corners
SPIN=($'\xe2\xa0\x8b' $'\xe2\xa0\x99' $'\xe2\xa0\xb9' $'\xe2\xa0\xb8' $'\xe2\xa0\xbc' \
      $'\xe2\xa0\xb4' $'\xe2\xa0\xa6' $'\xe2\xa0\xa7' $'\xe2\xa0\x87' $'\xe2\xa0\x8f')

# state gathered during setup, rendered as a summary box at the end
S_LOCALE=pending; S_KEYRING=pending; S_UPDATE=pending; S_USER=pending
USER_LABEL="User"
STEP_VALUE=""; STEP_STATUS=ok

_rep()  { local s="$1" n="$2" out=""; while (( n-- > 0 )); do out+="$s"; done; printf '%s' "$out"; }
_pad()  { local n=$(( $2 - ${#1} )); (( n < 0 )) && n=0; printf '%s%*s' "$1" "$n" ''; }
_lead() { printf '[%s/4] %s' "$1" "$(_pad "$2" "$LBLW")"; }
RULE="$(_rep "$BH" 59)"

_run_line() {  # <n> <label> <spinner-frame> : in-place "running" line
  printf '%s  %s %s%s %s %s%s%s ' "$CR" "$(_lead "$1" "$2")" \
    "$DM" "$RARR" "$(_pad "Running$ELL" "$VALW")" "$DM" "$3" "$RS"
}
_done_line() {  # <n> <label> <value> <ok|skip|fail>
  local g="$PND" gc="$DM"
  [ "$4" = ok ] && { g="$CHK"; gc="$GN"; }
  printf '%s  %s %s%s%s %s %s%s%s \n' "$CR" "$(_lead "$1" "$2")" \
    "$DM" "$RARR" "$RS" "$(_pad "$3" "$VALW")" "$gc" "$g" "$RS"
}
_spin() { local i=0; while :; do _run_line "$1" "$2" "${SPIN[i % 10]}"; i=$((i+1)); sleep 0.1; done; }

SPIN_PID=""
spin_start() { STEP_VALUE=""; STEP_STATUS=ok; if [ "$TTY" = yes ]; then _spin "$1" "$2" & SPIN_PID=$!; fi; }
spin_stop()  { [ -n "$SPIN_PID" ] && { kill "$SPIN_PID" 2>/dev/null; wait "$SPIN_PID" 2>/dev/null; }; SPIN_PID=""; }

w_locale() {
  local culture="" mapped ps
  ps="$(command -v powershell.exe || true)"
  if [ "$UNATTENDED" = no ] && [ -n "$ps" ]; then
    for _ in 1 2 3 4 5; do
      culture="$("$ps" -NoProfile -NonInteractive -Command '(Get-Culture).Name' 2>/dev/null | tr -d '\r\n')"
      [[ "$culture" == *-* ]] && break; culture=""; sleep 1
    done
  fi
  [ -n "$culture" ] || culture="$(oobe_conf_get "$OOBE_CONF" locale "en-US" 2>/dev/null || echo en-US)"
  if declare -F map_windows_locale >/dev/null; then mapped="$(map_windows_locale "$culture")"; else mapped="en_US.UTF-8"; fi
  sed -i "s/^#\\(${mapped} UTF-8\\)/\\1/" /etc/locale.gen 2>/dev/null || true
  locale-gen >/dev/null 2>&1 || true
  echo "LANG=$mapped" > /etc/locale.conf 2>/dev/null || true
  S_LOCALE=ok; STEP_VALUE="$mapped"
}
w_keyring() {
  pacman-key --init >/dev/null 2>&1 || true
  pacman-key --populate archlinux cachyos >/dev/null 2>&1 || true
  S_KEYRING=ok; STEP_VALUE="Keyring ready"
}
w_update() {
  if [ "$RUN_UPDATE" != yes ]; then
    S_UPDATE=skip; STEP_STATUS=skip; STEP_VALUE="Skipped"; return 0
  fi
  if pacman -Syu --noconfirm </dev/null >"$UPDATE_LOG" 2>&1; then
    S_UPDATE=ok; STEP_VALUE="Packages updated"
  else
    S_UPDATE=fail; STEP_STATUS=fail; STEP_VALUE="Update failed"
  fi
}

_set_default_user() {
  grep -q '^\[user\]' /etc/wsl.conf 2>/dev/null || printf '\n[user]\ndefault=%s\n' "$1" >> /etc/wsl.conf
}
_provision_user() {
  local username="$1" grouplist="$2" shell="$3" groups="" g
  for g in ${grouplist//,/ }; do getent group "$g" >/dev/null 2>&1 && groups="${groups:+$groups,}$g"; done
  if ! id -u "$username" >/dev/null 2>&1; then
    useradd --create-home --uid 1000 ${groups:+--groups "$groups"} --shell "$shell" "$username" 2>/dev/null || {
      printf '  %serror:%s could not create user %s\n' "$DM" "$RS" "$username" >&2; return 1; }
  fi
  _set_default_user "$username"
}

create_user() {  # step 4: interactive prompt, or unattended from oobe.conf
  local username shell grouplist pw pw2
  if [ "$UNATTENDED" = yes ]; then
    username="$CONF_USER"
    if ! validate_username "$username"; then
      S_USER=skip; _done_line 4 'Configure User Account' 'Invalid username' skip
      printf '  %sinvalid username in %s: %s (leaving a root shell)%s\n' "$DM" "$OOBE_CONF" "$username" "$RS" >&2
      return 0
    fi
    shell="$(oobe_conf_get "$OOBE_CONF" shell /usr/bin/fish)"; [ -x "$shell" ] || shell=/usr/bin/fish
    grouplist="$(oobe_conf_get "$OOBE_CONF" groups "$DEFAULT_GROUPS")"
    if _provision_user "$username" "$grouplist" "$shell"; then
      S_USER=ok; USER_LABEL="User ($username)"; _done_line 4 'Configure User Account' "$username" ok
    else
      S_USER=skip; _done_line 4 'Configure User Account' 'Not created' skip
    fi
    return 0
  fi

  # Step 4 stays "Running…" while the account is collected; the box confirms it.
  printf '  %s %s%s%s Running%s\n\n' "$(_lead 4 'Configure User Account')" "$DM" "$RARR" "$RS" "$ELL"
  printf '%s%s%s\n\n' "$TEAL" "$RULE" "$RS"
  printf ' Please create a default UNIX user account.\n'
  printf ' The username does not need to match your Windows username.\n'
  printf '  %sFor more information visit: https://aka.ms/wslusers%s\n\n' "$DM" "$RS"

  while :; do
    if ! read -r -p "$(printf '%s%s%s Choose a username: ' "$TEAL" "$ARR" "$RS")" username; then
      S_USER=skip
      printf '  %sno input — skipping user creation%s\n' "$DM" "$RS"
      printf '  %slater: useradd -m -G wheel -s /usr/bin/fish <name> && passwd <name>%s\n' "$DM" "$RS"
      return 0
    fi
    [ -z "$username" ] && continue
    if id -u "$username" >/dev/null 2>&1; then _set_default_user "$username"; S_USER=ok; USER_LABEL="User ($username)"; return 0; fi
    validate_username "$username" && break
    printf '  %sinvalid %s lowercase letter/_ first, then letters/digits/-/_ , max 32%s\n' "$DM" "$ELL" "$RS"
  done
  _provision_user "$username" "$DEFAULT_GROUPS" /usr/bin/fish || { S_USER=skip; return 0; }
  while :; do
    read -rs -p "$(printf '%s%s%s Choose a password: ' "$TEAL" "$ARR" "$RS")" pw; printf '\n'
    read -rs -p "$(printf '%s%s%s Confirm password: ' "$TEAL" "$ARR" "$RS")" pw2; printf '\n'
    [ -n "$pw" ] && [ "$pw" = "$pw2" ] && break
    printf '  %spasswords did not match — try again%s\n' "$DM" "$RS"
  done
  printf '%s:%s' "$username" "$pw" | chpasswd 2>/dev/null || true
  S_USER=ok; USER_LABEL="User ($username)"
}

_box_row() {  # <label> <status>
  local label="$1" g="$PND" gc="$DM" dots
  [ "$2" = ok ] && { g="$CHK"; gc="$GN"; }
  dots="$(_rep '.' $(( 57 - ${#label} - 5 )))"
  printf '%s%s%s %s %s%s%s %s%s%s %s%s%s\n' \
    "$TEAL" "$BV" "$RS" "$label" "$DM" "$dots" "$RS" "$gc" "$g" "$RS" "$TEAL" "$BV" "$RS"
}
summary() {
  printf '\n%s%s%s CachyOS on WSL %s%s%s\n' "$TEAL" "$BTL" "$BH" "$(_rep "$BH" 40)" "$BTR" "$RS"
  _box_row "Locale"      "$S_LOCALE"
  _box_row "Keyring"     "$S_KEYRING"
  _box_row "Update"      "$S_UPDATE"
  _box_row "$USER_LABEL" "$S_USER"
  printf '%s%s%s%s%s\n' "$TEAL" "$BBL" "$(_rep "$BH" 57)" "$BBR" "$RS"
}

# --- unattended detection + update policy ---
UNATTENDED=no; CONF_USER=""
if command -v oobe_conf_get >/dev/null 2>&1; then
  CONF_USER="$(oobe_conf_get "$OOBE_CONF" username "")"
  [ -n "$CONF_USER" ] && UNATTENDED=yes
fi
RUN_UPDATE=yes
if command -v oobe_bool >/dev/null 2>&1; then
  [ "$(oobe_bool "$(oobe_conf_get "$OOBE_CONF" run_update yes)")" = yes ] || RUN_UPDATE=no
fi

# --- flow ---
printf '\n%s%s%s\n' "$TEAL" "$RULE" "$RS"
printf '%s Welcome to CachyOS on WSL%s\n' "$BTEAL" "$RS"
printf '%s%s%s\n' "$TEAL" "$RULE" "$RS"
printf '%s %s First-run Setup%s\n' "$DM" "$ELB" "$RS"
printf '\n Provisioning the new WSL instance %s%s%s\n' "$TEAL" "${WSL_DISTRO_NAME:-CachyOS}" "$RS"
printf '  %sThis might take a while%s%s\n\n' "$DM" "$ELL" "$RS"

spin_start 1 'Configure Locale';       w_locale;  spin_stop; _done_line 1 'Configure Locale'       "$STEP_VALUE" "$STEP_STATUS"
spin_start 2 'Initialize Keyring';     w_keyring; spin_stop; _done_line 2 'Initialize Keyring'     "$STEP_VALUE" "$STEP_STATUS"
spin_start 3 'Update System Packages'; w_update;  spin_stop; _done_line 3 'Update System Packages' "$STEP_VALUE" "$STEP_STATUS"
create_user
summary
[ "$S_UPDATE" = fail ] && printf '  %supdate failed — see %s; run '\''sudo pacman -Syu'\'' later%s\n' "$DM" "$UPDATE_LOG" "$RS"
printf '\n%sReady.%s Welcome to CachyOS.\n\n' "$GN" "$RS"
exit 0
