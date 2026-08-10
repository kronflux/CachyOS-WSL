#!/usr/bin/env bats
load helpers
setup() {
  setup_tmpdir; D="$TEST_TMPDIR/out"; mkdir -p "$D"
  printf 'dummy\n' > "$D/cachyos-v3-2026.08.09.7.wsl"
  ( cd "$D" && sha256sum "cachyos-v3-2026.08.09.7.wsl" > "cachyos-v3-2026.08.09.7.wsl.sha256" )
}
teardown() { teardown_tmpdir; }

@test "emits valid JSON with the v3 entry" {
  run "$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.09.7 "$D"
  assert_success
  echo "$output" | jq -e '.ModernDistributions.CachyOS | length == 1' >/dev/null
}
@test "v3 is Default, names+url+sha correct" {
  out="$("$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.09.7 "$D")"
  echo "$out" | jq -e '.ModernDistributions.CachyOS[] | select(.Name=="CachyOS") | .Default == true' >/dev/null
  echo "$out" | jq -e '[.ModernDistributions.CachyOS[].Name] == ["CachyOS"]' >/dev/null
  echo "$out" | jq -e '.ModernDistributions.CachyOS[0].Amd64Url.Url | test("kronflux/CachyOS-WSL/releases/download/2026.08.09.7/")' >/dev/null
  want="$(awk '{print $1}' "$D/cachyos-v3-2026.08.09.7.wsl.sha256")"
  got="$(echo "$out" | jq -r '.ModernDistributions.CachyOS[] | select(.Name=="CachyOS") | .Amd64Url.Sha256')"
  [ "$want" = "$got" ]
}
@test "emits no entry when the image is absent" {
  rm "$D"/cachyos-v3-*.wsl*
  run "$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.09.7 "$D"
  echo "$output" | jq -e '.ModernDistributions.CachyOS | length == 0' >/dev/null
}
