#!/usr/bin/env bats
load helpers

@test "passes on a well-formed rootfs" {
  run "$REPO_ROOT/scripts/validate-rootfs.sh" "$REPO_ROOT/tests/fixtures/rootfs-good"
  assert_success
}

@test "fails when a prohibited file is present and JSON is invalid" {
  run "$REPO_ROOT/scripts/validate-rootfs.sh" "$REPO_ROOT/tests/fixtures/rootfs-bad"
  assert_failure
  assert_output --partial "resolv.conf"
}

@test "fails when wsl.conf is missing" {
  tmp="$(mktemp -d)"; cp -r "$REPO_ROOT/tests/fixtures/rootfs-good/." "$tmp"
  rm "$tmp/etc/wsl.conf"
  run "$REPO_ROOT/scripts/validate-rootfs.sh" "$tmp"
  rm -rf "$tmp"
  assert_failure
  assert_output --partial "wsl.conf"
}

@test "fails when WSLInterop binfmt is missing" {
  tmp="$(mktemp -d)"; cp -r "$REPO_ROOT/tests/fixtures/rootfs-good/." "$tmp"
  rm -f "$tmp/etc/binfmt.d/WSLInterop.conf"
  run "$REPO_ROOT/scripts/validate-rootfs.sh" "$tmp"; rm -rf "$tmp"
  assert_failure
  assert_output --partial "WSLInterop"
}
@test "passes good fixture with the P2 files present" {
  run "$REPO_ROOT/scripts/validate-rootfs.sh" "$REPO_ROOT/tests/fixtures/rootfs-good"
  assert_success
}
