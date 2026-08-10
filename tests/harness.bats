#!/usr/bin/env bats
load helpers

@test "bats harness and assertions work" {
  run echo "hello"
  assert_success
  assert_output "hello"
}

@test "REPO_ROOT points at the repository root" {
  assert [ -f "$REPO_ROOT/tests/helpers.bash" ]
}
