#!/usr/bin/env bats
load helpers

setup() { source "$REPO_ROOT/scripts/lib/locale-map.sh"; }

@test "maps en-US to en_US.UTF-8" {
  run map_windows_locale "en-US"
  assert_success
  assert_output "en_US.UTF-8"
}

@test "maps de-DE to de_DE.UTF-8" {
  run map_windows_locale "de-DE"
  assert_output "de_DE.UTF-8"
}

@test "maps ja-JP to ja_JP.UTF-8" {
  run map_windows_locale "ja-JP"
  assert_output "ja_JP.UTF-8"
}

@test "language-only culture falls back to en_US.UTF-8" {
  run map_windows_locale "en"
  assert_output "en_US.UTF-8"
}

@test "empty input falls back to en_US.UTF-8" {
  run map_windows_locale ""
  assert_output "en_US.UTF-8"
}

@test "strips trailing CR from PowerShell output" {
  run map_windows_locale $'fr-FR\r'
  assert_output "fr_FR.UTF-8"
}

@test "a culture with no glibc locale falls back to en_US.UTF-8" {
  LOCALE_SUPPORTED="$REPO_ROOT/tests/fixtures/i18n-SUPPORTED" run map_windows_locale "bogus-XX"
  assert_output "en_US.UTF-8"
}

@test "a culture with a script subtag maps to its language and region" {
  LOCALE_SUPPORTED="$REPO_ROOT/tests/fixtures/i18n-SUPPORTED" run map_windows_locale "zh-Hans-CN"
  assert_output "zh_CN.UTF-8"
}
