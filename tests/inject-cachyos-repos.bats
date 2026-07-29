#!/usr/bin/env bats
load helpers

setup() { setup_tmpdir; }
teardown() { teardown_tmpdir; }

@test "v3 tier injects CachyOS v3 repos in place" {
  cp "$REPO_ROOT/tests/fixtures/pacman.base.conf" "$TEST_TMPDIR/pacman.conf"
  run "$REPO_ROOT/scripts/inject-cachyos-repos.sh" v3 "$TEST_TMPDIR/pacman.conf"
  assert_success
  run diff -u "$REPO_ROOT/tests/fixtures/pacman.v3.expected" "$TEST_TMPDIR/pacman.conf"
  assert_success
}

@test "v4 tier injects v4 repo stanza" {
  cp "$REPO_ROOT/tests/fixtures/pacman.base.conf" "$TEST_TMPDIR/pacman.conf"
  run "$REPO_ROOT/scripts/inject-cachyos-repos.sh" v4 "$TEST_TMPDIR/pacman.conf"
  assert_success
  assert grep -q '^\[cachyos-core-v4\]' "$TEST_TMPDIR/pacman.conf"
}

@test "znver4 tier injects znver4 repo stanza" {
  cp "$REPO_ROOT/tests/fixtures/pacman.base.conf" "$TEST_TMPDIR/pacman.conf"
  run "$REPO_ROOT/scripts/inject-cachyos-repos.sh" znver4 "$TEST_TMPDIR/pacman.conf"
  assert_success
  assert grep -q '^\[cachyos-core-znver4\]' "$TEST_TMPDIR/pacman.conf"
}

@test "rejects unknown tier" {
  cp "$REPO_ROOT/tests/fixtures/pacman.base.conf" "$TEST_TMPDIR/pacman.conf"
  run "$REPO_ROOT/scripts/inject-cachyos-repos.sh" v9 "$TEST_TMPDIR/pacman.conf"
  assert_failure
  assert_output --partial "unknown tier"
}

@test "rejects missing pacman.conf" {
  run "$REPO_ROOT/scripts/inject-cachyos-repos.sh" v3 "$TEST_TMPDIR/nope.conf"
  assert_failure
  assert_output --partial "not found"
}
