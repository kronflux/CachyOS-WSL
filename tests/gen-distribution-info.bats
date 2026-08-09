#!/usr/bin/env bats
load helpers
setup() {
  setup_tmpdir; D="$TEST_TMPDIR/out"; mkdir -p "$D"
  for t in v3 v4 znver4; do
    printf 'dummy\n' > "$D/cachyos-$t-2026.08.09.7.wsl"
    ( cd "$D" && sha256sum "cachyos-$t-2026.08.09.7.wsl" > "cachyos-$t-2026.08.09.7.wsl.sha256" )
  done
}
teardown() { teardown_tmpdir; }

@test "emits valid JSON with 3 tier entries" {
  run "$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.09.7 "$D"
  assert_success
  echo "$output" | jq -e '.ModernDistributions.CachyOS | length == 3' >/dev/null
}
@test "v3 is Default, names+url+sha correct" {
  out="$("$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.09.7 "$D")"
  echo "$out" | jq -e '.ModernDistributions.CachyOS[] | select(.Name=="CachyOS") | .Default == true' >/dev/null
  echo "$out" | jq -e '[.ModernDistributions.CachyOS[].Name] == ["CachyOS","CachyOS_v4","CachyOS_Zen4"]' >/dev/null
  echo "$out" | jq -e '.ModernDistributions.CachyOS[0].Amd64Url.Url | test("kronflux/CachyOS-WSL/releases/download/2026.08.09.7/")' >/dev/null
  want="$(awk '{print $1}' "$D/cachyos-v3-2026.08.09.7.wsl.sha256")"
  got="$(echo "$out" | jq -r '.ModernDistributions.CachyOS[] | select(.Name=="CachyOS") | .Amd64Url.Sha256')"
  [ "$want" = "$got" ]
}
@test "skips a missing tier" {
  rm "$D"/cachyos-znver4-*.wsl*
  run "$REPO_ROOT/scripts/gen-distribution-info.sh" 2026.08.09.7 "$D"
  echo "$output" | jq -e '.ModernDistributions.CachyOS | length == 2' >/dev/null
}
