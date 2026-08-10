#!/usr/bin/env bats
load helpers
setup() {
  setup_tmpdir; D="$TEST_TMPDIR/out"; mkdir -p "$D"
  printf 'dummy\n' > "$D/cachyos-2026.08.09.7.wsl"
  ( cd "$D" && sha256sum "cachyos-2026.08.09.7.wsl" > "cachyos-2026.08.09.7.wsl.sha256" )
}
teardown() { teardown_tmpdir; }

@test "emits valid JSON with one entry" {
  run "$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.09.7 "$D"
  assert_success
  echo "$output" | jq -e '.ModernDistributions.CachyOS | length == 1' >/dev/null
}
@test "the entry is Default, names+url+sha correct" {
  out="$("$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.09.7 "$D")"
  echo "$out" | jq -e '.ModernDistributions.CachyOS[0] | .Name == "CachyOS" and .FriendlyName == "CachyOS" and .Default == true' >/dev/null
  echo "$out" | jq -e '.ModernDistributions.CachyOS[0].Amd64Url.Url == "https://github.com/kronflux/CachyOS-WSL/releases/download/2026.08.09.7/cachyos-2026.08.09.7.wsl"' >/dev/null
  want="$(awk '{print $1}' "$D/cachyos-2026.08.09.7.wsl.sha256")"
  got="$(echo "$out" | jq -r '.ModernDistributions.CachyOS[0].Amd64Url.Sha256')"
  [ "$want" = "$got" ]
}
@test "emits no entry when the image for the tag is absent" {
  run "$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.10.1 "$D"
  assert_success
  echo "$output" | jq -e '.ModernDistributions.CachyOS | length == 0' >/dev/null
}
