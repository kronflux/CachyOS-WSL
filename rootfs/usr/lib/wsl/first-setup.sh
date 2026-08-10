#!/usr/bin/env bash
# CachyWSL out-of-box experience. WSL runs it on the first interactive launch and
# again on every launch until it exits 0 (a non-zero exit blocks the shell for that
# launch). Interactive setup exits non-zero until a UID 1000 account with a password
# exists, so an interrupted setup resumes on the next launch. Every step is safe to
# repeat. Sourcing the file defines the functions without running the flow.
set -uo pipefail

# Count code points (not bytes) so the padded columns line up, independent of the
# locale being configured below. C.UTF-8 is built into glibc.
locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$' && export LC_ALL=C.UTF-8

OOBE_LIB_DIR="${OOBE_LIB_DIR:-/usr/lib/wsl}"
# shellcheck source=/dev/null
source "$OOBE_LIB_DIR/oobe-lib.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$OOBE_LIB_DIR/locale-map.sh" 2>/dev/null || true
command -v validate_username >/dev/null 2>&1 || validate_username() {
  case "${1:-}" in root|daemon|bin|sys|nobody) return 1 ;; esac
  [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

OOBE_CONF=/etc/wsl/oobe.conf
WSL_CONF="${WSL_CONF:-/etc/wsl.conf}"
DEFAULT_UID=1000
DEFAULT_GROUPS="sys,network,rfkill,users,video,storage,lp,audio,wheel"
SETUP_LOG="${SETUP_LOG:-/var/log/cachywsl-firstboot.log}"
OPTIMIZE_CMD="${OPTIMIZE_CMD:-/usr/lib/wsl/optimize-repos}"
STEPS=6   # setup steps; the user account is the last one
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
S_LOCALE=pending; S_KEYRING=pending; S_MIRRORS=pending; S_OPTIMIZE=pending
S_UPDATE=pending; S_USER=pending
USER_LABEL="User"
STEP_VALUE=""; STEP_STATUS=ok

_rep()  { local s="$1" n="$2" out=""; while (( n-- > 0 )); do out+="$s"; done; printf '%s' "$out"; }
_pad()  { local n=$(( $2 - ${#1} )); (( n < 0 )) && n=0; printf '%s%*s' "$1" "$n" ''; }
_lead() { printf '[%s/%s] %s' "$1" "$STEPS" "$(_pad "$2" "$LBLW")"; }
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
# Waits with the read builtin on a pipe that never receives data: the spinner
# starts no external program, so it keeps working while pacman replaces glibc.
_spin() {
  local i=0 tick
  exec {tick}<> <(:)
  while :; do _run_line "$1" "$2" "${SPIN[i % 10]}"; i=$((i+1)); read -rt 0.1 -u "$tick" _ || :; done
}

SPIN_PID=""
spin_start() { STEP_VALUE=""; STEP_STATUS=ok; if [ "$TTY" = yes ]; then _spin "$1" "$2" & SPIN_PID=$!; fi; }
spin_stop()  { [ -n "$SPIN_PID" ] && { kill "$SPIN_PID" 2>/dev/null; wait "$SPIN_PID" 2>/dev/null; }; SPIN_PID=""; }

w_locale() {
  local culture="" mapped ps
  ps="$(command -v powershell.exe || true)"
  if [ "$UNATTENDED" = no ] && [ -n "$ps" ]; then
    for _ in 1 2 3 4 5; do
      culture="$("$ps" -NoProfile -NonInteractive -Command '(Get-Culture).Name' </dev/null 2>/dev/null | tr -d '\r\n')"
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
  if pacman-key --init >/dev/null 2>&1 && pacman-key --populate archlinux cachyos >/dev/null 2>&1; then
    S_KEYRING=ok; STEP_VALUE="Keyring ready"
  else
    S_KEYRING=fail; STEP_STATUS=fail; STEP_VALUE="Keyring failed"
  fi
}
w_mirrors() {  # non-fatal: the shipped mirrorlists work anywhere, possibly slower
  if cachyos-rate-mirrors </dev/null >>"$SETUP_LOG" 2>&1; then
    S_MIRRORS=ok; STEP_VALUE="Mirrors ranked"
  else
    S_MIRRORS=skip; STEP_STATUS=skip; STEP_VALUE="Kept defaults"
  fi
}
w_optimize() {  # non-fatal: the generic packages run on any x86-64 CPU
  local level
  if [ "$RUN_OPTIMIZE" != yes ]; then
    S_OPTIMIZE=skip; STEP_STATUS=skip; STEP_VALUE="Skipped"; return 0
  fi
  if "$OPTIMIZE_CMD" </dev/null >>"$SETUP_LOG" 2>&1; then
    level="$(grep -m1 -oE '^\[cachyos-(v3|v4|znver4)\]$' /etc/pacman.conf 2>/dev/null | tr -d '[]')"
    S_OPTIMIZE=ok; STEP_VALUE="${level:-generic (CPU)}"
  else
    S_OPTIMIZE=fail; STEP_STATUS=fail; STEP_VALUE="Kept generic"
  fi
}
w_update() {
  if [ "$RUN_UPDATE" != yes ]; then
    S_UPDATE=skip; STEP_STATUS=skip; STEP_VALUE="Skipped"; return 0
  fi
  if pacman -Syu --noconfirm </dev/null >>"$SETUP_LOG" 2>&1; then
    S_UPDATE=ok; STEP_VALUE="Packages updated"
  else
    S_UPDATE=fail; STEP_STATUS=fail; STEP_VALUE="Update failed"
  fi
}

# Sets default=<user> in the [user] section of wsl.conf, adding the section or the
# key when missing. Used by `wsl --import` installs, which ignore defaultUid.
_set_default_user() {
  if ! grep -q '^\[user\]' "$WSL_CONF" 2>/dev/null; then
    printf '\n[user]\ndefault=%s\n' "$1" >> "$WSL_CONF"
  elif sed -n '/^\[user\]/,/^\[/p' "$WSL_CONF" | grep -qE '^default[[:space:]]*='; then
    sed -i "/^\[user\]/,/^\[/s/^default[[:space:]]*=.*/default=$1/" "$WSL_CONF"
  else
    sed -i "/^\[user\]/a default=$1" "$WSL_CONF"
  fi
}
_provision_user() {  # <username> <comma-separated groups> <shell>; skips an existing account
  local username="$1" grouplist="$2" shell="$3" groups="" g
  for g in ${grouplist//,/ }; do getent group "$g" >/dev/null 2>&1 && groups="${groups:+$groups,}$g"; done
  id -u "$username" >/dev/null 2>&1 && return 0
  useradd --create-home --uid "$DEFAULT_UID" ${groups:+--groups "$groups"} --shell "$shell" "$username" 2>/dev/null || {
    printf '  %serror:%s could not create user %s\n' "$DM" "$RS" "$username" >&2; return 1; }
}
_has_password() { [ "$(passwd -S -- "$1" 2>/dev/null | awk '{print $2}')" = P ]; }
_set_password() {  # <username>: prompts until a password is set; returns 1 when input closes
  local username="$1" pw pw2
  while :; do
    read -rs -p "$(printf '%s%s%s Choose a password: ' "$TEAL" "$ARR" "$RS")" pw || { printf '\n'; return 1; }
    printf '\n'
    read -rs -p "$(printf '%s%s%s Confirm password: ' "$TEAL" "$ARR" "$RS")" pw2 || { printf '\n'; return 1; }
    printf '\n'
    if [ -z "$pw" ] || [ "$pw" != "$pw2" ]; then
      printf '  %spasswords did not match — try again%s\n' "$DM" "$RS"; continue
    fi
    printf '%s:%s\n' "$username" "$pw" | chpasswd 2>/dev/null && return 0
    printf '  %scould not set the password — try again%s\n' "$DM" "$RS"
  done
}

create_user() {  # step 4: interactive prompt, or unattended from oobe.conf
  local username shell grouplist
  if [ "$UNATTENDED" = yes ]; then
    username="$CONF_USER"
    if ! validate_username "$username"; then
      S_USER=skip; _done_line "$STEPS" 'Configure User Account' 'Invalid username' skip
      printf '  %sinvalid username in %s: %s (leaving a root shell)%s\n' "$DM" "$OOBE_CONF" "$username" "$RS" >&2
      return 0
    fi
    shell="$(oobe_conf_get "$OOBE_CONF" shell /usr/bin/fish)"; [ -x "$shell" ] || shell=/usr/bin/fish
    grouplist="$(oobe_conf_get "$OOBE_CONF" groups "$DEFAULT_GROUPS")"
    if _provision_user "$username" "$grouplist" "$shell"; then
      _set_default_user "$username"
      S_USER=ok; USER_LABEL="User ($username)"; _done_line "$STEPS" 'Configure User Account' "$username" ok
    else
      S_USER=skip; _done_line "$STEPS" 'Configure User Account' 'Not created' skip
    fi
    return 0
  fi

  # The account step stays "Running…" while the account is collected; the box confirms it.
  printf '  %s %s%s%s Running%s\n\n' "$(_lead "$STEPS" 'Configure User Account')" "$DM" "$RARR" "$RS" "$ELL"
  printf '%s%s%s\n\n' "$TEAL" "$RULE" "$RS"

  # A UID 1000 account left by an interrupted earlier run is resumed, not recreated.
  username="$(getent passwd "$DEFAULT_UID" | cut -d: -f1)"
  if [ -n "$username" ]; then
    printf ' Continuing setup of the user account %s%s%s.\n\n' "$TEAL" "$username" "$RS"
  else
    printf ' Please create a default UNIX user account.\n'
    printf ' The username does not need to match your Windows username.\n'
    printf '  %sFor more information visit: https://aka.ms/wslusers%s\n\n' "$DM" "$RS"
    while :; do
      if ! read -r -p "$(printf '%s%s%s Choose a username: ' "$TEAL" "$ARR" "$RS")" username; then
        printf '\n'; S_USER=fail; return 1
      fi
      [ -z "$username" ] && continue
      if ! validate_username "$username"; then
        printf '  %sinvalid %s lowercase letter/_ first, then letters/digits/-/_ , max 32%s\n' "$DM" "$ELL" "$RS"
        continue
      fi
      if id -u "$username" >/dev/null 2>&1; then
        printf '  %s%s is a system account — choose another name%s\n' "$DM" "$username" "$RS"
        continue
      fi
      _provision_user "$username" "$DEFAULT_GROUPS" /usr/bin/fish || { S_USER=fail; return 1; }
      break
    done
  fi
  _set_default_user "$username"
  if ! _has_password "$username"; then
    _set_password "$username" || { S_USER=fail; return 1; }
  fi
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
  _box_row "Mirrors"     "$S_MIRRORS"
  _box_row "Optimized packages" "$S_OPTIMIZE"
  _box_row "Update"      "$S_UPDATE"
  _box_row "$USER_LABEL" "$S_USER"
  printf '%s%s%s%s%s\n' "$TEAL" "$BBL" "$(_rep "$BH" 57)" "$BBR" "$RS"
}

# Interactive setup is finished only once the account exists with a password; until
# then WSL reruns the OOBE on the next launch. Unattended setup always finishes: an
# invalid oobe.conf username leaves a root shell by design.
oobe_exit_code() {
  if [ "$UNATTENDED" = no ] && [ "$S_USER" != ok ]; then echo 1; else echo 0; fi
}

main() {
  trap 'spin_stop; printf "\n  %sSetup interrupted — it continues on the next launch.%s\n" "$DM" "$RS"; exit 1' INT TERM

  # --- unattended detection + update policy ---
  UNATTENDED=no; CONF_USER=""
  if command -v oobe_conf_get >/dev/null 2>&1; then
    CONF_USER="$(oobe_conf_get "$OOBE_CONF" username "")"
    [ -n "$CONF_USER" ] && UNATTENDED=yes
  fi
  RUN_UPDATE=yes; RUN_OPTIMIZE=yes
  if command -v oobe_bool >/dev/null 2>&1; then
    [ "$(oobe_bool "$(oobe_conf_get "$OOBE_CONF" run_update yes)")" = yes ] || RUN_UPDATE=no
    [ "$(oobe_bool "$(oobe_conf_get "$OOBE_CONF" optimize yes)")" = yes ] || RUN_OPTIMIZE=no
  fi

  printf '\n%s%s%s\n' "$TEAL" "$RULE" "$RS"
  printf '%s Welcome to CachyOS on WSL%s\n' "$BTEAL" "$RS"
  printf '%s%s%s\n' "$TEAL" "$RULE" "$RS"
  printf '%s %s First-run Setup%s\n' "$DM" "$ELB" "$RS"
  printf '\n Provisioning the new WSL instance %s%s%s\n' "$TEAL" "${WSL_DISTRO_NAME:-CachyOS}" "$RS"
  printf '  %sThis might take a while%s%s\n' "$DM" "$ELL" "$RS"
  printf '  %sReport issues at https://github.com/kronflux/CachyOS-WSL/issues%s\n\n' "$DM" "$RS"

  spin_start 1 'Configure Locale';       w_locale;  spin_stop; _done_line 1 'Configure Locale'       "$STEP_VALUE" "$STEP_STATUS"
  spin_start 2 'Initialize Keyring';     w_keyring; spin_stop; _done_line 2 'Initialize Keyring'     "$STEP_VALUE" "$STEP_STATUS"
  spin_start 3 'Rank Mirrors';           w_mirrors; spin_stop; _done_line 3 'Rank Mirrors'           "$STEP_VALUE" "$STEP_STATUS"
  spin_start 4 'Optimize for this CPU';  w_optimize; spin_stop; _done_line 4 'Optimize for this CPU' "$STEP_VALUE" "$STEP_STATUS"
  spin_start 5 'Update System Packages'; w_update;  spin_stop; _done_line 5 'Update System Packages' "$STEP_VALUE" "$STEP_STATUS"
  create_user
  summary
  [ "$S_KEYRING" = fail ] && printf '  %skeyring setup failed; run '\''sudo pacman-key --init && sudo pacman-key --populate'\''%s\n' "$DM" "$RS"
  [ "$S_OPTIMIZE" = fail ] && printf '  %soptimization failed — see %s; run '\''sudo /usr/lib/wsl/optimize-repos'\'' later%s\n' "$DM" "$SETUP_LOG" "$RS"
  [ "$S_UPDATE" = fail ] && printf '  %supdate failed — see %s; run '\''sudo pacman -Syu'\'' later%s\n' "$DM" "$SETUP_LOG" "$RS"
  if [ "$(oobe_exit_code)" -ne 0 ]; then
    printf '\n  %sNo user account yet — setup continues on the next launch.%s\n\n' "$DM" "$RS"
    exit 1
  fi
  printf '\n%sReady.%s Welcome to CachyOS.\n\n' "$GN" "$RS"
  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
