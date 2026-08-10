#!/usr/bin/env bats
load helpers
setup() { setup_tmpdir; }
teardown() { teardown_tmpdir; }

@test "verify-vendor passes on intact tree" {
  run "$REPO_ROOT/scripts/verify-vendor.sh"
  assert_success
}
@test "verify-vendor fails when an asset is modified" {
  cp "$REPO_ROOT/vendor/makepkg/x86_64_v3.conf" "$TEST_TMPDIR/backup"
  echo "# tampered" >> "$REPO_ROOT/vendor/makepkg/x86_64_v3.conf"
  run "$REPO_ROOT/scripts/verify-vendor.sh"
  cp "$TEST_TMPDIR/backup" "$REPO_ROOT/vendor/makepkg/x86_64_v3.conf"
  assert_failure
}
