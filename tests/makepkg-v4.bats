#!/usr/bin/env bats
load helpers
V4="$REPO_ROOT/vendor/makepkg/x86_64_v4.conf"
V3="$REPO_ROOT/vendor/makepkg/x86_64_v3.conf"

@test "v4 preset exists" { assert [ -f "$V4" ]; }
@test "v4 sets CARCH x86_64_v4" { run grep -E '^CARCH="?x86_64_v4' "$V4"; assert_success; }
@test "v4 march is x86-64-v4" { run grep -E '\-march=x86-64-v4' "$V4"; assert_success; }
@test "no v3 arch tokens leak into v4" {
  run grep -E 'x86-64-v3|x86_64_v3' "$V4"; assert_failure
}
@test "v4 keeps v3 LTO/hardening lines (only arch differs)" {
  run diff <(sed -E 's/x86_64_v3/x86_64_v4/g; s/x86-64-v3/x86-64-v4/g' "$V3") "$V4"
  assert_success
}
