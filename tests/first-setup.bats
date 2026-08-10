#!/usr/bin/env bats
# OOBE account, default-user, keyring and exit-code behaviour, with the system
# account tools replaced by shell functions backed by a flat users file.
load helpers

BATS_TEST_TIMEOUT=20

setup() {
  setup_tmpdir
  export OOBE_LIB_DIR="$REPO_ROOT/scripts/lib"
  export WSL_CONF="$TEST_TMPDIR/wsl.conf"
  export LOCALE_SUPPORTED="$REPO_ROOT/tests/fixtures/i18n-SUPPORTED"
  printf '[boot]\nsystemd=true\n' > "$WSL_CONF"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/rootfs/usr/lib/wsl/first-setup.sh"
  # first-setup.sh enables nounset and pipefail for its own run; bats internals need them off.
  set +u +o pipefail

  # users file: name:uid:passwd-state (P = usable password, L = locked)
  USERS="$TEST_TMPDIR/users"
  printf 'root:0:L\nhttp:33:L\n' > "$USERS"
  getent() {
    case "$1" in
      group) return 0 ;;
      passwd) awk -F: -v k="$2" '($1==k || $2==k) { print $1 ":x:" $2 ":" $2 "::/home/" $1 ":/usr/bin/fish"; f=1 } END { exit !f }' "$USERS" ;;
    esac
  }
  id() { [ "$1" = -u ] && awk -F: -v k="$2" '$1==k { print $2; f=1 } END { exit !f }' "$USERS"; }
  useradd() { printf '%s:1000:L\n' "${*: -1}" >> "$USERS"; }
  passwd() { [ "$1" = -S ] && awk -F: -v k="${*: -1}" '$1==k { print $1 " " $3 }' "$USERS"; }
  chpasswd() { local line name; read -r line; name="${line%%:*}"; sed -i "s/^$name:\([0-9]*\):.*/$name:\1:P/" "$USERS"; }
}
teardown() { teardown_tmpdir; }

@test "interactive: rejects root and existing system accounts, then creates the entered user" {
  create_user < <(printf 'root\nhttp\ndev\npw\npw\n') 2>/dev/null
  [ "$S_USER" = ok ]
  grep -qx 'dev:1000:P' "$USERS"
  grep -qx 'root:0:L' "$USERS"
  grep -qx 'default=dev' "$WSL_CONF"
}

@test "rerun after an interrupted setup: existing UID 1000 without a password is asked for one" {
  printf 'dev:1000:L\n' >> "$USERS"
  create_user < <(printf 'pw\npw\n') 2>/dev/null
  [ "$S_USER" = ok ]
  grep -qx 'dev:1000:P' "$USERS"
  ! grep -q '^pw:' "$USERS"
  grep -qx 'default=dev' "$WSL_CONF"
}

@test "rerun with a complete UID 1000 account asks for nothing" {
  printf 'dev:1000:P\n' >> "$USERS"
  create_user < /dev/null 2>/dev/null
  [ "$S_USER" = ok ]
  grep -qx 'default=dev' "$WSL_CONF"
}

@test "closed input during password entry fails instead of looping" {
  printf 'dev:1000:L\n' >> "$USERS"
  run create_user < /dev/null
  assert_failure
}

@test "closed input at the username prompt fails" {
  run create_user < /dev/null
  assert_failure
}

@test "_set_default_user replaces the default in an existing [user] section" {
  printf '[boot]\nsystemd=true\n\n[user]\ndefault=old\n\n[network]\ngenerateHosts=true\n' > "$WSL_CONF"
  _set_default_user dev
  grep -qx 'default=dev' "$WSL_CONF"
  [ "$(grep -c '^default' "$WSL_CONF")" -eq 1 ]
  grep -qx 'generateHosts=true' "$WSL_CONF"
}

@test "_set_default_user adds a default to a [user] section that has none" {
  printf '[user]\n\n[network]\ngenerateHosts=true\n' > "$WSL_CONF"
  _set_default_user dev
  [ "$(sed -n '/^\[user\]/,/^\[network\]/p' "$WSL_CONF" | grep -c '^default=dev$')" -eq 1 ]
}

@test "a keyring failure is reported as a failure" {
  pacman-key() { return 1; }
  w_keyring
  [ "$S_KEYRING" = fail ]
}

@test "interactive setup without a user exits non-zero so WSL runs it again" {
  UNATTENDED=no; S_USER=fail
  run oobe_exit_code
  assert_output 1
}

@test "completed interactive setup exits zero" {
  UNATTENDED=no; S_USER=ok
  run oobe_exit_code
  assert_output 0
}

@test "unattended setup with an invalid username still exits zero (root shell by design)" {
  UNATTENDED=yes; S_USER=skip
  run oobe_exit_code
  assert_output 0
}

@test "optimization turned off in oobe.conf is skipped without running the optimizer" {
  export SETUP_LOG="$TEST_TMPDIR/setup.log" OPTIMIZE_CMD="$TEST_TMPDIR/optimizer"
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$TEST_TMPDIR" > "$OPTIMIZE_CMD"; chmod +x "$OPTIMIZE_CMD"
  RUN_OPTIMIZE=no; STEP_STATUS=ok
  w_optimize
  [ "$S_OPTIMIZE" = skip ]
  [ ! -e "$TEST_TMPDIR/ran" ]
}

@test "an optimizer failure is reported and keeps the generic packages" {
  export SETUP_LOG="$TEST_TMPDIR/setup.log" OPTIMIZE_CMD=false
  RUN_OPTIMIZE=yes; STEP_STATUS=ok
  w_optimize
  [ "$S_OPTIMIZE" = fail ]
  [ "$STEP_VALUE" = "Kept generic" ]
}

@test "the spinner keeps its pace and stays silent when no external program can start" {
  # An empty PATH stands in for a glibc upgrade, during which every dynamically
  # linked program fails to load.
  PATH='' _spin 4 'Optimize for this CPU' >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err" &
  local pid=$!
  sleep 0.35
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  [ ! -s "$TEST_TMPDIR/err" ]
  frames="$(grep -o Running "$TEST_TMPDIR/out" | wc -l)"
  [ "$frames" -ge 2 ] && [ "$frames" -le 6 ]
}
