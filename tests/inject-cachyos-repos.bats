#!/usr/bin/env bats
load helpers

setup() { setup_tmpdir; }
teardown() { teardown_tmpdir; }

@test "injects CachyOS v3 repos in place" {
  cp "$REPO_ROOT/tests/fixtures/pacman.base.conf" "$TEST_TMPDIR/pacman.conf"
  run "$REPO_ROOT/scripts/inject-cachyos-repos.sh" "$TEST_TMPDIR/pacman.conf"
  assert_success
  run diff -u "$REPO_ROOT/tests/fixtures/pacman.v3.expected" "$TEST_TMPDIR/pacman.conf"
  assert_success
}

@test "rejects missing pacman.conf" {
  run "$REPO_ROOT/scripts/inject-cachyos-repos.sh" "$TEST_TMPDIR/nope.conf"
  assert_failure
  assert_output --partial "not found"
}
