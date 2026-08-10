#!/usr/bin/env bats
load helpers
setup() { setup_tmpdir; source "$REPO_ROOT/scripts/lib/oobe-lib.sh"; }
teardown() { teardown_tmpdir; }

@test "validate_username accepts valid names" {
  for n in dev my_user a _x user-1 abcdefghijklmnopqrstuvwxyz012345; do
    run validate_username "$n"; assert_success
  done
}
@test "validate_username rejects invalid names" {
  for n in "" Dev 1dev root "dev!" "a b" abcdefghijklmnopqrstuvwxyz0123456; do
    run validate_username "$n"; assert_failure
  done
}
@test "validate_username rejects multiline / newline names" {
  run validate_username $'dev\nroot'
  assert_failure
  run validate_username $'root\ndev'
  assert_failure
  run validate_username $'dev\n; rm -rf /'
  assert_failure
}
@test "oobe_conf_get reads keys, ignores comments, applies default" {
  f="$TEST_TMPDIR/c"; printf '# comment\nusername = dev\nshell="/usr/bin/fish"\n' > "$f"
  run oobe_conf_get "$f" username;            assert_output "dev"
  run oobe_conf_get "$f" shell;               assert_output "/usr/bin/fish"
  run oobe_conf_get "$f" missing default_x;   assert_output "default_x"
  run oobe_conf_get /nonexistent user fb;     assert_output "fb"
}
@test "oobe_bool normalizes truthy/falsy" {
  for v in yes Y true 1 YES; do run oobe_bool "$v"; assert_output "yes"; done
  for v in no n false 0 "" garbage; do run oobe_bool "$v"; assert_output "no"; done
}
