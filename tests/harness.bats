#!/usr/bin/env bats
load helpers

@test "bats harness and assertions work" {
  run echo "hello"
  assert_success
  assert_output "hello"
}

@test "REPO_ROOT points at a dir containing docs/" {
  assert [ -d "$REPO_ROOT/docs" ]
}
