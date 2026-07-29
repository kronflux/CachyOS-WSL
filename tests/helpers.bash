#!/usr/bin/env bash
# Shared setup for bats tests.
load "test_helper/bats-support/load"
load "test_helper/bats-assert/load"

# Absolute path to the repo root (parent of tests/).
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
export REPO_ROOT

# Make a throwaway temp dir per test; auto-cleaned in teardown.
setup_tmpdir() {
  TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cachywsl.XXXXXX")"
  export TEST_TMPDIR
}

teardown_tmpdir() {
  [ -n "${TEST_TMPDIR:-}" ] && rm -rf "$TEST_TMPDIR"
}
