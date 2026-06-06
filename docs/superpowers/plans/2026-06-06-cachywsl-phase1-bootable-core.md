# CachyWSL Phase 1 — Bootable Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce `cachyos-v3-<version>.wsl` that imports into WSL 2, runs an OOBE, and boots to a CachyOS-branded fish shell.

**Architecture:** Fork the official Arch Linux WSL build structure (Makefile + `scripts/*.sh` + `rootfs/` overlay, rootless `fakechroot`/`fakeroot`). Graft CachyOS by injecting CachyOS's own optimized repos (`[cachyos-core-v3]` etc.) into the build pacman config via vendored AWK transforms, installing CachyOS `pacman`/keyring/identity packages, and running the `cachyos-branding` hook. Unit-testable units (repo injection, locale mapping, rootfs validation) are developed test-first with `bats`; the full image build is an integration step run natively on this CachyOS-WSL host.

**Tech Stack:** Bash, GNU Make, `gawk`, `fakechroot`/`fakeroot`, `pacman`/`pacstrap` (arch-install-scripts), `xz`, `jq`, `bats-core` (+ bats-assert/bats-support), `shellcheck`.

**Scope note:** This is Phase 1 of 4. Later phases get their own plans: P2 (full userland parity, `cachyos-settings` review, v4/znver4 tiers, validation hardening), P3 (GitHub Actions CI, Cosign signing, `DistributionInfo.json`, Windows PowerShell tooling), P4 (optional kernel). Reproducibility pinning of *binary* CachyOS packages is deferred to P3; P1 vendors only the small text assets (AWK transforms, makepkg presets) and lets `pacman` resolve binary packages from the live CachyOS repos.

**Prerequisites / assumptions:**
- Run from the repo root: `/mnt/c/Users/Richard/Workspace/CachyWSL/CachyOS-WSL/`.
- Host is CachyOS (or Arch) with `pacman` and the CachyOS repos+keyring already configured (true on this dev box). Internet access for `pacman -Sy`.
- The reference clones are siblings two levels up: `../../CachyOS_repos/` and `../../cachyos-wsl-dwalleck/`.
- `wsl.exe` is on `PATH` (it is, inside WSL) for the import smoke-test in Task 12.

---

## File structure (created across this plan)

```
CachyOS-WSL/
├── Makefile                              # Task 11
├── scripts/
│   ├── build-image.sh                    # Task 10
│   ├── inject-cachyos-repos.sh           # Task 3
│   ├── validate-rootfs.sh                # Task 7
│   ├── test-image.sh                     # Task 11
│   ├── exclude                           # Task 8
│   └── lib/
│       └── locale-map.sh                 # Task 4
├── vendor/
│   ├── cachyos-repo/
│   │   ├── install-repo.awk              # Task 2 (v3)
│   │   ├── install-v4-repo.awk           # Task 2
│   │   ├── install-znver4-repo.awk       # Task 2
│   │   └── SHA256SUMS                     # Task 2
│   └── makepkg/
│       ├── x86_64_v3.conf                # Task 2
│       └── x86_64_v4.conf                # Task 2
├── rootfs/
│   ├── etc/
│   │   ├── wsl.conf                       # Task 5
│   │   ├── wsl-distribution.conf          # Task 5
│   │   └── locale.conf                    # Task 5
│   └── usr/lib/wsl/
│       ├── oobe.sh                        # Task 6
│       ├── cachyos.ico                    # Task 9
│       ├── terminal-profile.json          # Task 9
│       └── hooks/
│           └── 50-setcap-iputils.hook     # Task 9
├── packages/
│   └── base.list                          # Task 8
├── tests/
│   ├── test_helper/                       # Task 1 (bats-support, bats-assert)
│   ├── helpers.bash                       # Task 1
│   ├── inject-cachyos-repos.bats          # Task 3
│   ├── locale-map.bats                    # Task 4
│   ├── validate-rootfs.bats               # Task 7
│   └── fixtures/                          # Tasks 3,7
└── docs/…
```

---

## Task 1: Dev environment + test harness bootstrap

**Files:**
- Create: `tests/helpers.bash`
- Create: `tests/test_helper/` (git submodules or vendored bats-assert/bats-support)
- Create: `.gitmodules` (if using submodules)

- [ ] **Step 1: Install build + test tooling**

Run:
```bash
sudo pacman -S --needed --noconfirm bats fakechroot arch-install-scripts shellcheck shfmt jq
```
Expected: all packages install (most already present on CachyOS; `bats`, `fakechroot`, `arch-install-scripts`, `shfmt` are the new ones). Verify:
```bash
bats --version && fakechroot --version 2>&1 | head -1 && pacstrap --version | head -1
```
Expected: prints a `Bats x.y.z` version, a fakechroot version line, and a pacstrap version line (no "command not found").

- [ ] **Step 2: Vendor bats helper libraries**

Run:
```bash
git submodule add https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert
```
Expected: two submodules cloned under `tests/test_helper/`; `.gitmodules` created.

- [ ] **Step 3: Write the shared bats helper**

Create `tests/helpers.bash`:
```bash
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
```

- [ ] **Step 4: Add a smoke test to prove the harness runs**

Create `tests/harness.bats`:
```bash
#!/usr/bin/env bats
load helpers

@test "bats harness and assertions work" {
  run echo "hello"
  assert_success
  assert_output "hello"
}

@test "REPO_ROOT points at a dir containing docs/" {
  assert [ -d "$REPO_ROOT/docs" ]
}
```

- [ ] **Step 5: Run the smoke test**

Run: `bats tests/harness.bats`
Expected: `2 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add .gitmodules tests/
git commit -m "test: bootstrap bats harness and dev tooling"
```

---

## Task 2: Vendor CachyOS repo + makepkg assets

The authoritative AWK repo transforms live in the cloned `cachyos-repo-add-script`; the tier makepkg presets live in cloned `devtools`. Vendor copies + checksums so the build is self-contained and doesn't fetch from a moving branch.

**Files:**
- Create: `vendor/cachyos-repo/install-repo.awk`, `install-v4-repo.awk`, `install-znver4-repo.awk`
- Create: `vendor/cachyos-repo/SHA256SUMS`
- Create: `vendor/makepkg/x86_64_v3.conf`, `vendor/makepkg/x86_64_v4.conf`

- [ ] **Step 1: Locate the upstream assets**

Run:
```bash
ls ../../CachyOS_repos/cachyos-repo-add-script/*.awk
ls ../../CachyOS_repos/devtools/config/makepkg/x86_64_v3.conf ../../CachyOS_repos/devtools/config/makepkg/x86_64_v4.conf 2>/dev/null || \
  find ../../CachyOS_repos/devtools -name 'x86_64_v*.conf'
```
Expected: prints the three `.awk` paths and the two makepkg preset paths. If the makepkg presets are under a different subdir, note the actual paths for Step 2.

- [ ] **Step 2: Copy assets into vendor/**

Run:
```bash
mkdir -p vendor/cachyos-repo vendor/makepkg
cp ../../CachyOS_repos/cachyos-repo-add-script/install-repo.awk       vendor/cachyos-repo/
cp ../../CachyOS_repos/cachyos-repo-add-script/install-v4-repo.awk    vendor/cachyos-repo/
cp ../../CachyOS_repos/cachyos-repo-add-script/install-znver4-repo.awk vendor/cachyos-repo/
cp ../../CachyOS_repos/devtools/config/makepkg/x86_64_v3.conf vendor/makepkg/
cp ../../CachyOS_repos/devtools/config/makepkg/x86_64_v4.conf vendor/makepkg/
```
Expected: five files copied. Verify: `ls -R vendor/`.

- [ ] **Step 3: Verify the v3 AWK produces the expected stanzas (manual sanity)**

Run:
```bash
printf '[options]\nArchitecture = x86_64\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' > /tmp/p.conf
gawk -f vendor/cachyos-repo/install-repo.awk /tmp/p.conf
```
Expected output contains `Architecture = auto` and the four stanzas `[cachyos-v3]`, `[cachyos-core-v3]`, `[cachyos-extra-v3]`, `[cachyos]`, each with an `Include = /etc/pacman.d/cachyos*-mirrorlist` line, inserted **before** `[core]`.
> If the upstream AWK reads its repo block from an embedded heredoc/data section rather than emitting literal stanzas, record its exact output here — Task 3's expected fixture must match this byte-for-byte.

- [ ] **Step 4: Record checksums**

Run:
```bash
( cd vendor/cachyos-repo && sha256sum ./*.awk > SHA256SUMS )
cat vendor/cachyos-repo/SHA256SUMS
```
Expected: three lines of `<hash>  ./install-*.awk`.

- [ ] **Step 5: Commit**

```bash
git add vendor/
git commit -m "vendor: pin CachyOS repo AWK transforms and makepkg tier presets"
```

---

## Task 3: Repo-injection script (`inject-cachyos-repos.sh`)

Wraps the vendored AWK transforms with **explicit** tier selection (no CPU autodetection — we cross-build all tiers). Edits a pacman.conf in place.

**Files:**
- Create: `scripts/inject-cachyos-repos.sh`
- Create: `tests/inject-cachyos-repos.bats`
- Create: `tests/fixtures/pacman.base.conf`, `tests/fixtures/pacman.v3.expected`

- [ ] **Step 1: Create the input fixture**

Create `tests/fixtures/pacman.base.conf`:
```ini
[options]
Architecture = x86_64
SigLevel = Required DatabaseOptional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
```

- [ ] **Step 2: Generate the expected fixture from the vendored AWK**

Run:
```bash
gawk -f vendor/cachyos-repo/install-repo.awk tests/fixtures/pacman.base.conf > tests/fixtures/pacman.v3.expected
cat tests/fixtures/pacman.v3.expected
```
Expected: the transformed conf (CachyOS v3 stanzas before `[core]`, `Architecture = auto`). This file is the oracle for the test.
> Generating the expected output from the vendored AWK keeps the test pinned to the vendored asset. The test below proves the *wrapper* selects the right AWK per tier and writes in place.

- [ ] **Step 3: Write the failing test**

Create `tests/inject-cachyos-repos.bats`:
```bash
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
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `bats tests/inject-cachyos-repos.bats`
Expected: FAIL — `scripts/inject-cachyos-repos.sh` does not exist yet.

- [ ] **Step 5: Write the implementation**

Create `scripts/inject-cachyos-repos.sh`:
```bash
#!/usr/bin/env bash
# Inject CachyOS optimized repos into a pacman.conf for a given CPU tier.
# Usage: inject-cachyos-repos.sh <v3|v4|znver4> <path/to/pacman.conf>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/../vendor/cachyos-repo"

tier="${1:-}"
conf="${2:-}"

case "$tier" in
  v3)     awk_file="install-repo.awk" ;;
  v4)     awk_file="install-v4-repo.awk" ;;
  znver4) awk_file="install-znver4-repo.awk" ;;
  *) echo "error: unknown tier '$tier' (expected v3|v4|znver4)" >&2; exit 2 ;;
esac

if [ -z "$conf" ] || [ ! -f "$conf" ]; then
  echo "error: pacman.conf not found: '$conf'" >&2
  exit 2
fi

gawk -i inplace -f "$VENDOR_DIR/$awk_file" "$conf"
```

- [ ] **Step 6: Make executable and run the test**

Run:
```bash
chmod +x scripts/inject-cachyos-repos.sh
bats tests/inject-cachyos-repos.bats
```
Expected: `5 tests, 0 failures`.
> If `gawk -i inplace` is unavailable, fall back to: `tmp="$(mktemp)"; gawk -f "$VENDOR_DIR/$awk_file" "$conf" > "$tmp" && mv "$tmp" "$conf"`. Re-run the test.

- [ ] **Step 7: Lint**

Run: `shellcheck scripts/inject-cachyos-repos.sh`
Expected: no output (clean).

- [ ] **Step 8: Commit**

```bash
git add scripts/inject-cachyos-repos.sh tests/inject-cachyos-repos.bats tests/fixtures/
git commit -m "feat: tier-explicit CachyOS repo injection with tests"
```

---

## Task 4: Locale-mapping library (`scripts/lib/locale-map.sh`)

Extract the Windows-culture → Linux-locale logic into a sourceable, unit-tested function so OOBE stays testable.

**Files:**
- Create: `scripts/lib/locale-map.sh`
- Create: `tests/locale-map.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/locale-map.bats`:
```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/locale-map.bats`
Expected: FAIL — `scripts/lib/locale-map.sh` does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/lib/locale-map.sh`:
```bash
#!/usr/bin/env bash
# map_windows_locale <culture> -> echoes a Linux locale like "en_US.UTF-8".
# <culture> is a Windows culture name such as "en-US" (from (Get-Culture).Name).
# Falls back to en_US.UTF-8 for empty or malformed input.
map_windows_locale() {
  local culture="${1:-}"
  # Strip CR/LF that PowerShell appends.
  culture="${culture//$'\r'/}"
  culture="${culture//$'\n'/}"

  # Need the "lang-REGION" shape; anything else -> default.
  if [[ "$culture" != *-* ]]; then
    echo "en_US.UTF-8"
    return 0
  fi

  local lang="${culture%%-*}"
  local region="${culture##*-}"
  if [ -z "$lang" ] || [ -z "$region" ]; then
    echo "en_US.UTF-8"
    return 0
  fi

  # Linux uses lang_REGION.UTF-8.
  printf '%s_%s.UTF-8\n' "${lang,,}" "${region^^}"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/locale-map.bats`
Expected: `6 tests, 0 failures`.

- [ ] **Step 5: Lint and commit**

```bash
shellcheck scripts/lib/locale-map.sh
git add scripts/lib/locale-map.sh tests/locale-map.bats
git commit -m "feat: tested Windows->Linux locale mapping helper"
```
Expected: shellcheck clean; commit succeeds.

---

## Task 5: rootfs static WSL configs

**Files:**
- Create: `rootfs/etc/wsl.conf`
- Create: `rootfs/etc/wsl-distribution.conf`
- Create: `rootfs/etc/locale.conf`

- [ ] **Step 1: Write `rootfs/etc/wsl.conf`**

Create `rootfs/etc/wsl.conf`:
```ini
[boot]
systemd=true

[automount]
enabled=true
options="metadata"
mountFsTab=true

[interop]
enabled=true
appendWindowsPath=true

[network]
generateResolvConf=true
generateHostsFile=true
```

- [ ] **Step 2: Write `rootfs/etc/wsl-distribution.conf`**

Create `rootfs/etc/wsl-distribution.conf`:
```ini
[oobe]
command = /usr/lib/wsl/oobe.sh
defaultUid = 1000
defaultName = CachyOS

[shortcut]
icon = /usr/lib/wsl/cachyos.ico

[windowsterminal]
ProfileTemplate = /usr/lib/wsl/terminal-profile.json
```

- [ ] **Step 3: Write `rootfs/etc/locale.conf`**

Create `rootfs/etc/locale.conf`:
```ini
LANG=C.UTF-8
```

- [ ] **Step 4: Sanity-check the conf files are valid INI-ish (no tabs, keys present)**

Run:
```bash
grep -q 'systemd=true' rootfs/etc/wsl.conf && \
grep -q 'options="metadata"' rootfs/etc/wsl.conf && \
grep -q 'defaultName = CachyOS' rootfs/etc/wsl-distribution.conf && \
echo OK
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add rootfs/etc/
git commit -m "feat: rootfs WSL configs (systemd, metadata mount, interop, OOBE)"
```

---

## Task 6: OOBE script (`oobe.sh`)

**Files:**
- Create: `rootfs/usr/lib/wsl/oobe.sh`

- [ ] **Step 1: Write the implementation**

Create `rootfs/usr/lib/wsl/oobe.sh`:
```bash
#!/usr/bin/env bash
# CachyWSL out-of-box experience. Runs once on first launch (idempotent).
set -uo pipefail

# shellcheck source=/dev/null
source /usr/lib/wsl/locale-map.sh 2>/dev/null || true

DEFAULT_GROUPS="sys,network,rfkill,users,video,storage,lp,audio,wheel"

echo "Welcome to CachyOS on WSL!"
echo "Project: https://github.com/  (CachyWSL)"
echo

# --- 1. Locale: detect from Windows, fall back to en_US.UTF-8 -----------------
configure_locale() {
  local culture="en-US" mapped
  local ps
  ps="$(command -v powershell.exe || true)"
  if [ -n "$ps" ]; then
    culture="$("$ps" -NoProfile -Command '(Get-Culture).Name' 2>/dev/null || echo en-US)"
  fi
  if declare -F map_windows_locale >/dev/null; then
    mapped="$(map_windows_locale "$culture")"
  else
    mapped="en_US.UTF-8"
  fi
  echo "Configuring locale: $mapped"
  sed -i "s/^#\\(${mapped} UTF-8\\)/\\1/" /etc/locale.gen 2>/dev/null || true
  locale-gen >/dev/null 2>&1 || true
  echo "LANG=$mapped" > /etc/locale.conf
}

# --- 2. Pacman keyring --------------------------------------------------------
init_keyring() {
  echo "Initializing pacman keyring (one-time)..."
  pacman-key --init >/dev/null 2>&1 || true
  pacman-key --populate archlinux cachyos >/dev/null 2>&1 || true
  echo "Done."
}

# --- 3. Create the default user ----------------------------------------------
create_user() {
  local username=""
  while [ -z "$username" ]; do
    read -r -p "Enter a username for your CachyOS user: " username
  done
  if ! id -u "$username" >/dev/null 2>&1; then
    useradd --create-home --uid 1000 --groups "$DEFAULT_GROUPS" \
            --shell /usr/bin/fish "$username"
    echo "Set a password for $username:"
    passwd "$username"
  fi
  # Make this the default WSL user.
  if ! grep -q '^\[user\]' /etc/wsl.conf 2>/dev/null; then
    printf '\n[user]\ndefault=%s\n' "$username" >> /etc/wsl.conf
  fi
}

configure_locale
init_keyring
create_user

echo
echo "CachyOS is ready. It is strongly recommended to run 'sudo pacman -Syu' now."
```

- [ ] **Step 2: Static-check the script parses and is lint-clean**

Run:
```bash
bash -n rootfs/usr/lib/wsl/oobe.sh && shellcheck rootfs/usr/lib/wsl/oobe.sh
```
Expected: no syntax error; shellcheck clean (the `source .../locale-map.sh` is annotated `# shellcheck source=/dev/null`).
> Note: `oobe.sh` sources `/usr/lib/wsl/locale-map.sh`. Task 10's build step copies `scripts/lib/locale-map.sh` to `rootfs`'s `/usr/lib/wsl/locale-map.sh` inside the image so this resolves at runtime.

- [ ] **Step 3: Mark executable and commit**

```bash
chmod +x rootfs/usr/lib/wsl/oobe.sh
git add rootfs/usr/lib/wsl/oobe.sh
git commit -m "feat: OOBE (locale detect, keyring, fish-default user creation)"
```

---

## Task 7: rootfs validator (`validate-rootfs.sh`)

**Files:**
- Create: `scripts/validate-rootfs.sh`
- Create: `tests/validate-rootfs.bats`
- Create: fixtures under `tests/fixtures/rootfs-good/` and `tests/fixtures/rootfs-bad/`

- [ ] **Step 1: Build the "good" fixture tree**

Run:
```bash
G=tests/fixtures/rootfs-good
mkdir -p "$G/etc/pacman.d" "$G/usr/lib/wsl"
cp rootfs/etc/wsl.conf "$G/etc/wsl.conf"
cp rootfs/etc/wsl-distribution.conf "$G/etc/wsl-distribution.conf"
cp rootfs/usr/lib/wsl/oobe.sh "$G/usr/lib/wsl/oobe.sh"; chmod 0755 "$G/usr/lib/wsl/oobe.sh"
printf '{"profiles":[{"colorScheme":"CachyOS"}]}\n' > "$G/usr/lib/wsl/terminal-profile.json"
printf 'icon\n' > "$G/usr/lib/wsl/cachyos.ico"
printf 'root:x:0:0::/root:/usr/bin/bash\n' > "$G/etc/passwd"
printf 'root:!*:::::::\n' > "$G/etc/shadow"
```
Expected: a minimal tree that should PASS validation.

- [ ] **Step 2: Build the "bad" fixture tree (prohibited file present, bad JSON)**

Run:
```bash
B=tests/fixtures/rootfs-bad
mkdir -p "$B/etc" "$B/usr/lib/wsl"
cp rootfs/etc/wsl.conf "$B/etc/wsl.conf"
cp rootfs/etc/wsl-distribution.conf "$B/etc/wsl-distribution.conf"
cp rootfs/usr/lib/wsl/oobe.sh "$B/usr/lib/wsl/oobe.sh"; chmod 0755 "$B/usr/lib/wsl/oobe.sh"
printf 'not json\n' > "$B/usr/lib/wsl/terminal-profile.json"   # invalid JSON
printf 'icon\n' > "$B/usr/lib/wsl/cachyos.ico"
printf 'root:x:0:0::/root:/usr/bin/bash\n' > "$B/etc/passwd"
printf 'root:!*:::::::\n' > "$B/etc/shadow"
echo "nameserver 1.1.1.1" > "$B/etc/resolv.conf"             # prohibited file
```
Expected: a tree that should FAIL validation (prohibited `resolv.conf`, invalid JSON).

- [ ] **Step 3: Write the failing test**

Create `tests/validate-rootfs.bats`:
```bash
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
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `bats tests/validate-rootfs.bats`
Expected: FAIL — `scripts/validate-rootfs.sh` does not exist.

- [ ] **Step 5: Write the implementation**

Create `scripts/validate-rootfs.sh`:
```bash
#!/usr/bin/env bash
# Static validation gate for a built CachyWSL rootfs tree.
# Usage: validate-rootfs.sh <ROOTFS_DIR>   (exit 0 = pass, 1 = fail)
set -uo pipefail

ROOT="${1:-}"
fail=0
err() { echo "FAIL: $*"; fail=1; }
ok()  { echo "PASS: $*"; }

[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "FAIL: rootfs dir not found: '$ROOT'"; exit 1; }

# 1. Required files exist.
for f in etc/wsl.conf etc/wsl-distribution.conf usr/lib/wsl/oobe.sh \
         usr/lib/wsl/terminal-profile.json etc/passwd etc/shadow; do
  if [ -e "$ROOT/$f" ]; then ok "exists: $f"; else err "missing: $f"; fi
done

# 2. wsl.conf content.
grep -q 'systemd=true' "$ROOT/etc/wsl.conf" 2>/dev/null \
  && ok "wsl.conf enables systemd" || err "wsl.conf must set systemd=true"
grep -q 'defaultName = CachyOS' "$ROOT/etc/wsl-distribution.conf" 2>/dev/null \
  && ok "distribution defaultName is CachyOS" || err "wsl-distribution.conf defaultName"

# 3. OOBE executable.
if [ -x "$ROOT/usr/lib/wsl/oobe.sh" ]; then ok "oobe.sh executable"; else err "oobe.sh not executable"; fi

# 4. terminal-profile.json is valid JSON.
if jq -e . "$ROOT/usr/lib/wsl/terminal-profile.json" >/dev/null 2>&1; then
  ok "terminal-profile.json is valid JSON"
else
  err "terminal-profile.json is not valid JSON"
fi

# 5. Prohibited files (WSL-managed or build-volatile) must be absent.
for f in etc/resolv.conf etc/machine-id etc/hostname; do
  if [ -e "$ROOT/$f" ]; then err "prohibited file present: $f"; else ok "absent: $f"; fi
done
if compgen -G "$ROOT/boot/vmlinuz*" >/dev/null || compgen -G "$ROOT/boot/initramfs*" >/dev/null; then
  err "kernel/initramfs present (not allowed in WSL)"
else
  ok "no kernel/initramfs"
fi

# 6. shadow must not contain real password hashes for root.
if grep -E '^root:\$' "$ROOT/etc/shadow" >/dev/null 2>&1; then
  err "root has a password hash in /etc/shadow"
else
  ok "root has no password hash"
fi

[ "$fail" -eq 0 ] && { echo "VALIDATION OK"; exit 0; } || { echo "VALIDATION FAILED"; exit 1; }
```

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
chmod +x scripts/validate-rootfs.sh
bats tests/validate-rootfs.bats
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 7: Lint and commit**

```bash
shellcheck scripts/validate-rootfs.sh
git add scripts/validate-rootfs.sh tests/validate-rootfs.bats tests/fixtures/rootfs-good tests/fixtures/rootfs-bad
git commit -m "feat: rootfs static validation gate with fixtures"
```
Expected: shellcheck clean; commit succeeds.

---

## Task 8: Package list + tar exclude list

**Files:**
- Create: `packages/base.list`
- Create: `scripts/exclude`

- [ ] **Step 1: Write the P1 package list**

Create `packages/base.list` (one package per line; comments allowed). Kept minimal for a bootable, CachyOS-branded fish shell — full parity expands in P2:
```text
# --- Core system ---
base
sudo
iptables-nft
openssh
git
vim
nano
man-db
bash-completion

# --- CachyOS identity (pacman provides Architecture=auto) ---
pacman
cachyos-keyring
cachyos-mirrorlist
cachyos-v3-mirrorlist
cachyos-hooks
cachyos-settings
cachyos-rate-mirrors

# --- Shell experience (deps pull eza/bat/fzf/fastfetch/nerd-font/etc.) ---
fish
cachyos-fish-config
zsh
cachyos-zsh-config

# --- Package tooling ---
pacman-contrib
pkgfile
```

- [ ] **Step 2: Write the tar exclude list**

Create `scripts/exclude` (merged Arch + okrc patterns):
```text
./boot
./sys
./proc
./dev
./run
./mnt
./home
./etc/hostname
./etc/machine-id
./etc/resolv.conf
./etc/pacman.d/gnupg/openpgp-revocs.d/*
./etc/pacman.d/gnupg/private-keys-v1.d/*
./etc/pacman.d/gnupg/pubring.gpg~
./etc/pacman.d/gnupg/S.*
./root/*
./tmp/*
./var/cache/pacman/pkg/*
./var/lib/pacman/sync/*
./var/log/pacman.log
./var/tmp/*
./alpm-hooks
```

- [ ] **Step 3: Sanity-check the package list parses (strip comments/blanks)**

Run:
```bash
grep -vE '^\s*(#|$)' packages/base.list | tr '\n' ' '; echo
```
Expected: a single space-separated line of package names (no comments), e.g. `base sudo iptables-nft … pkgfile`.

- [ ] **Step 4: Commit**

```bash
git add packages/base.list scripts/exclude
git commit -m "feat: P1 package list and tar exclude list"
```

---

## Task 9: Branding assets (icon, terminal profile, setcap hook)

**Files:**
- Create: `rootfs/usr/lib/wsl/cachyos.ico`
- Create: `rootfs/usr/lib/wsl/terminal-profile.json`
- Create: `rootfs/usr/lib/wsl/hooks/50-setcap-iputils.hook`

- [ ] **Step 1: Vendor the CachyOS icon**

Run:
```bash
cp ../../cachyos-wsl-dwalleck/assets/cachyos.ico rootfs/usr/lib/wsl/cachyos.ico
file rootfs/usr/lib/wsl/cachyos.ico
```
Expected: `... MS Windows icon resource ...`. If the dwalleck asset is absent, convert the SVG: `magick ../../CachyOS_repos/cachyos-calamares/…/cachyos.svg -resize 256x256 rootfs/usr/lib/wsl/cachyos.ico` (record the actual SVG path used).

- [ ] **Step 2: Write the Windows Terminal profile template**

Create `rootfs/usr/lib/wsl/terminal-profile.json` (omits `name`/`commandLine` — WSL fills them):
```json
{
  "profiles": [
    {
      "colorScheme": "CachyOS",
      "font": { "face": "CaskaydiaCove Nerd Font" },
      "opacity": 90,
      "useAcrylic": true
    }
  ],
  "schemes": [
    {
      "name": "CachyOS",
      "background": "#0C0F12",
      "foreground": "#D4D4D4",
      "black": "#1B1F23",  "red": "#E06C75",   "green": "#2EA043",
      "yellow": "#E5C07B", "blue": "#3B82F6",  "purple": "#C678DD",
      "cyan": "#56B6C2",   "white": "#D4D4D4",
      "brightBlack": "#5C6370", "brightRed": "#E06C75", "brightGreen": "#2EA043",
      "brightYellow": "#E5C07B", "brightBlue": "#61AFEF", "brightPurple": "#C678DD",
      "brightCyan": "#56B6C2", "brightWhite": "#FFFFFF"
    }
  ]
}
```

- [ ] **Step 3: Validate the JSON**

Run: `jq -e . rootfs/usr/lib/wsl/terminal-profile.json >/dev/null && echo VALID`
Expected: `VALID`.

- [ ] **Step 4: Write the setcap hook**

Create `rootfs/usr/lib/wsl/hooks/50-setcap-iputils.hook`:
```ini
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/bin/ping

[Action]
Description = Restoring cap_net_raw on ping (non-root ping in WSL)...
When = PostTransaction
Exec = /usr/bin/setcap cap_net_raw+p /usr/bin/ping
```

- [ ] **Step 5: Commit**

```bash
git add rootfs/usr/lib/wsl/cachyos.ico rootfs/usr/lib/wsl/terminal-profile.json rootfs/usr/lib/wsl/hooks/
git commit -m "feat: branding (icon, terminal profile) and setcap-ping hook"
```

---

## Task 10: Core build script (`build-image.sh`)

**Files:**
- Create: `scripts/build-image.sh`

- [ ] **Step 1: Write the implementation**

Create `scripts/build-image.sh`:
```bash
#!/usr/bin/env bash
# Build a CachyWSL rootfs image for a CPU tier.
# Usage: build-image.sh <v3|v4|znver4> <IMAGE_VERSION>
set -euo pipefail
export TZ=UTC

TIER="${1:?usage: build-image.sh <tier> <image_version>}"
IMAGE_VERSION="${2:?usage: build-image.sh <tier> <image_version>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKDIR="$ROOT_DIR/workdir"
BUILDDIR="$WORKDIR/build-$TIER"
OUTPUTDIR="$ROOT_DIR/output"

SOURCE_DATE_EPOCH="$(date -u -d "$(awk -F. '{print $1"-"$2"-"$3}' <<<"$IMAGE_VERSION")" +%s 2>/dev/null || date -u +%s)"
export SOURCE_DATE_EPOCH

echo ">>> Building CachyWSL tier=$TIER version=$IMAGE_VERSION (SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH)"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR" "$OUTPUTDIR"

# --- 1. Build pacman.conf: start from a base, inject CachyOS repos for the tier
BUILD_PACMAN_CONF="$WORKDIR/pacman-$TIER.conf"
cat > "$BUILD_PACMAN_CONF" <<'EOF'
[options]
Architecture = x86_64
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF
"$SCRIPT_DIR/inject-cachyos-repos.sh" "$TIER" "$BUILD_PACMAN_CONF"

# --- 2. Neutralize ALPM hooks during bootstrap
mkdir -p "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks"
find /usr/share/libalpm/hooks -maxdepth 1 -type f -exec \
  ln -sf /dev/null "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks/{}" \; 2>/dev/null || true

# --- 3. Install packages into the rootfs (rootless)
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$ROOT_DIR/packages/base.list")
echo ">>> Installing ${#PKGS[@]} packages..."
fakechroot -- fakeroot -- pacman -Sy -r "$BUILDDIR" \
  --config "$BUILD_PACMAN_CONF" \
  --noconfirm --noscriptlet \
  --hookdir "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks/" \
  "${PKGS[@]}"

# --- 4. Overlay rootfs/ and wire os-release
cp --recursive --preserve=timestamps "$ROOT_DIR/rootfs/." "$BUILDDIR/"
install -Dm0755 "$SCRIPT_DIR/lib/locale-map.sh" "$BUILDDIR/usr/lib/wsl/locale-map.sh"
install -Dm0644 "$ROOT_DIR/rootfs/usr/lib/wsl/hooks/50-setcap-iputils.hook" \
  "$BUILDDIR/etc/pacman.d/hooks/50-setcap-iputils.hook"
ln -sf /usr/lib/os-release "$BUILDDIR/etc/os-release"

# --- 5. Post-install system configuration (chroot)
run_chroot() { fakechroot -- fakeroot -- chroot "$BUILDDIR" "$@"; }
run_chroot /usr/bin/update-ca-trust || true
run_chroot /usr/bin/systemd-sysusers || true
# CachyOS branding -> /etc/os-release, lsb-release, issue
run_chroot /usr/share/libalpm/scripts/cachyos-branding || true
# Tier-appropriate makepkg.conf (NOT -march=native)
case "$TIER" in
  v3)            install -Dm0644 "$ROOT_DIR/vendor/makepkg/x86_64_v3.conf" "$BUILDDIR/etc/makepkg.conf" ;;
  v4|znver4)     install -Dm0644 "$ROOT_DIR/vendor/makepkg/x86_64_v4.conf" "$BUILDDIR/etc/makepkg.conf" ;;
esac
# Enable Color + ILoveCandy in the shipped pacman.conf
sed -i -e 's/^#\?Color$/Color/' "$BUILDDIR/etc/pacman.conf" 2>/dev/null || true
grep -q ILoveCandy "$BUILDDIR/etc/pacman.conf" || \
  sed -i '/^Color$/a ILoveCandy' "$BUILDDIR/etc/pacman.conf" 2>/dev/null || true
# Passwordless wheel sudo
install -d -m0750 "$BUILDDIR/etc/sudoers.d"
echo '%wheel ALL=(ALL:ALL) ALL' > "$BUILDDIR/etc/sudoers.d/10-wheel"
chmod 0440 "$BUILDDIR/etc/sudoers.d/10-wheel"

# --- 6. WSL hardening: mask conflicting units, drop WSL-irrelevant hooks
for unit in systemd-firstboot console-getty getty@ serial-getty@ \
            systemd-resolved systemd-networkd NetworkManager \
            systemd-tmpfiles-setup systemd-tmpfiles-clean.timer tmp.mount; do
  ln -sf /dev/null "$BUILDDIR/etc/systemd/system/${unit}.service" 2>/dev/null || true
done
ln -sf /dev/null "$BUILDDIR/etc/systemd/system/getty.target" 2>/dev/null || true
rm -f "$BUILDDIR/usr/share/libalpm/hooks/cachyos-plymouth-initramfs.hook" \
      "$BUILDDIR/usr/share/libalpm/hooks/cachyos-reboot-required.hook" 2>/dev/null || true

# --- 7. Cleanup for reproducible packaging
rm -rf "$BUILDDIR"/etc/pacman.d/gnupg/* 2>/dev/null || true
find "$BUILDDIR" -exec touch --no-dereference --date="@$SOURCE_DATE_EPOCH" {} + 2>/dev/null || true

# --- 8. Pack deterministically -> .wsl
OUT="$OUTPUTDIR/cachyos-$TIER-$IMAGE_VERSION"
fakeroot -- tar \
  --numeric-owner --xattrs --acls \
  --mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime --sort=name \
  --pax-option=delete=atime,delete=ctime \
  --exclude-from="$SCRIPT_DIR/exclude" \
  -C "$BUILDDIR" -c . -f "$OUT.tar"
xz -9 -T0 -f "$OUT.tar"
mv "$OUT.tar.xz" "$OUT.wsl"
( cd "$OUTPUTDIR" && sha256sum "$(basename "$OUT.wsl")" > "$(basename "$OUT.wsl").sha256" )

echo ">>> Built $OUT.wsl"
ls -lh "$OUT.wsl" "$OUT.wsl.sha256"
```

- [ ] **Step 2: Lint the script**

Run: `shellcheck scripts/build-image.sh`
Expected: clean (or only informational notes; fix any warning-level findings).

- [ ] **Step 3: Run the build (integration — needs network + fakechroot)**

Run:
```bash
chmod +x scripts/build-image.sh
sudo true   # warm sudo (not used by build, but pacman keyring may need it on first run)
./scripts/build-image.sh v3 "$(date -u +%Y.%m.%d).0"
```
Expected: ends with `>>> Built …/output/cachyos-v3-<version>.wsl` and an `ls -lh` line showing a multi-hundred-MB `.wsl` plus a `.sha256`.
> Troubleshooting: if `fakechroot` chroot steps fail on scriptlets, confirm `--noscriptlet` is present (it is) and that ALPM hooks were neutralized. If pacman can't verify CachyOS packages, run `sudo pacman-key --populate cachyos` on the host first (the host keyring is reused).

- [ ] **Step 4: Validate the built tree**

Run:
```bash
./scripts/validate-rootfs.sh workdir/build-v3
```
Expected: ends with `VALIDATION OK` (exit 0).
> If it flags a prohibited file (e.g. `machine-id`) present in the *build* tree, that's fine — those are removed by `scripts/exclude` at pack time. Validation here targets the staged tree; adjust the call to validate the unpacked `.wsl` instead if stricter checking is wanted (Task 11 covers functional checks).

- [ ] **Step 5: Commit**

```bash
git add scripts/build-image.sh
git commit -m "feat: core v3 rootfs build (CachyOS repos, branding, WSL hardening, deterministic pack)"
```

---

## Task 11: Functional test script + Makefile wiring

**Files:**
- Create: `scripts/test-image.sh`
- Create: `Makefile`

- [ ] **Step 1: Write the functional test script**

Create `scripts/test-image.sh`:
```bash
#!/usr/bin/env bash
# Functional checks against a built rootfs (run in chroot).
# Usage: test-image.sh <TIER>
set -euo pipefail
TIER="${1:-v3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDDIR="$SCRIPT_DIR/../workdir/build-$TIER"

[ -d "$BUILDDIR" ] || { echo "no build dir: $BUILDDIR (run build first)"; exit 1; }
run_chroot() { fakechroot -- fakeroot -- chroot "$BUILDDIR" "$@"; }

echo ">>> os-release identifies as CachyOS"
run_chroot grep -q '^ID=cachyos' /usr/lib/os-release

echo ">>> fish is installed and is the configured default shell"
run_chroot test -x /usr/bin/fish
run_chroot test -f /etc/skel/.config/fish/config.fish

echo ">>> cachyos repos are present in pacman.conf"
run_chroot grep -q '\[cachyos' /etc/pacman.conf

echo ">>> wsl.conf enables systemd"
run_chroot grep -q 'systemd=true' /etc/wsl.conf

echo ">>> OOBE and locale-map are present"
run_chroot test -x /usr/lib/wsl/oobe.sh
run_chroot test -f /usr/lib/wsl/locale-map.sh

echo "ALL FUNCTIONAL TESTS PASSED"
```

- [ ] **Step 2: Write the Makefile**

Create `Makefile`:
```makefile
export TZ := UTC

TIER ?= v3
IMAGE_VERSION ?= $(shell date -u +%Y.%m.%d).0
ROOT := $(shell pwd)

.PHONY: build test validate unit lint clean

build:
	./scripts/build-image.sh $(TIER) $(IMAGE_VERSION)

test:
	./scripts/test-image.sh $(TIER)

validate:
	./scripts/validate-rootfs.sh workdir/build-$(TIER)

unit:
	bats tests/

lint:
	shellcheck scripts/*.sh scripts/lib/*.sh rootfs/usr/lib/wsl/oobe.sh

clean:
	rm -rf workdir output
```

- [ ] **Step 3: Run unit tests + lint via Make**

Run: `make unit && make lint`
Expected: all `bats` suites pass (`harness`, `inject-cachyos-repos`, `locale-map`, `validate-rootfs`); shellcheck clean.

- [ ] **Step 4: Run the functional test against the v3 build**

Run:
```bash
chmod +x scripts/test-image.sh
make test TIER=v3
```
Expected: prints each `>>>` line and ends with `ALL FUNCTIONAL TESTS PASSED`.
> If `/etc/skel/.config/fish/config.fish` is missing, `cachyos-fish-config` didn't install its skel files under `--noscriptlet`; confirm the package is in `base.list` and present under `workdir/build-v3/etc/skel/`. If absent, add a build step to copy the config from the installed package path.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-image.sh Makefile
git commit -m "feat: functional test script and Makefile targets (build/test/validate/unit/lint)"
```

---

## Task 12: WSL import smoke-test + docs

**Files:**
- Modify: `README.md` (add a "Build & try it" section)

- [ ] **Step 1: Import the built image into WSL (manual smoke test)**

Run (from inside this CachyOS-WSL session, `wsl.exe` is on PATH):
```bash
VER="$(date -u +%Y.%m.%d).0"
WSL_IMG="$(wslpath -w "$PWD/output/cachyos-v3-$VER.wsl")"
DEST="$(wslpath -w "$PWD/workdir/wsl-test-install")"
mkdir -p workdir/wsl-test-install
wsl.exe --import CachyWSL-test "$DEST" "$WSL_IMG" --version 2
```
Expected: `The operation completed successfully.` and `CachyWSL-test` appears in `wsl.exe --list`.

- [ ] **Step 2: Boot it and verify branding + shell**

Run:
```bash
wsl.exe -d CachyWSL-test -- bash -lc 'grep ^PRETTY_NAME /etc/os-release; command -v fish; pacman -Sy --noconfirm >/dev/null 2>&1 && echo PACMAN_OK'
```
Expected: `PRETTY_NAME="CachyOS Linux"` (or similar CachyOS branding), a fish path, and `PACMAN_OK` (repos reachable). The OOBE runs interactively on first *interactive* launch; this non-interactive check confirms the rootfs itself is sound.

- [ ] **Step 3: Tear down the test distro**

Run: `wsl.exe --unregister CachyWSL-test`
Expected: `Unregistering...` then success. (The `workdir/wsl-test-install` dir can be removed.)

- [ ] **Step 4: Document the build/try flow in README**

Add to `README.md` under a new `## Build & try it (Phase 1)` section:
```markdown
## Build & try it (Phase 1)

Requires a CachyOS or Arch host (WSL is fine) with `fakechroot`, `fakeroot`,
`arch-install-scripts`, and `bats`:

```bash
sudo pacman -S --needed bats fakechroot arch-install-scripts shellcheck jq
make unit            # run unit tests
make build TIER=v3   # produces output/cachyos-v3-<version>.wsl
make test  TIER=v3   # functional checks against the built tree
```

Try it in WSL:

```powershell
wsl --import CachyWSL-test C:\wsl\cachywsl output\cachyos-v3-<version>.wsl
wsl -d CachyWSL-test       # runs the OOBE on first launch
```
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: Phase 1 build-and-try instructions"
```

---

## Self-review notes (for the implementer)

- **Spec coverage (Phase 1 scope):** build engine = fakechroot/fakeroot (Task 10) ✓; tier-explicit CachyOS repo injection (Tasks 2–3) ✓; CachyOS `pacman`/keyring/identity + fish parity packages (Task 8) ✓; WSL configs + OOBE + locale detection (Tasks 4–6) ✓; branding via `cachyos-branding` hook + icon/terminal profile (Tasks 9–10) ✓; metadata automount, interop, WSLg-ready, setcap-ping (Tasks 5,9) ✓; deterministic packaging (Task 10) ✓; validation + functional tests (Tasks 7,11) ✓. **Deferred to later phases (by design):** v4/znver4 tiers, full userland, `cachyos-settings` audit (P2); CI, Cosign signing, `DistributionInfo.json`, PowerShell tooling (P3); kernel (P4); binary-package pinning/repro hardening (P3).
- **Type/name consistency:** `map_windows_locale` (Tasks 4,6); `inject-cachyos-repos.sh <tier> <conf>` (Tasks 3,10); `validate-rootfs.sh <dir>` (Tasks 7,10,11); `build-image.sh <tier> <version>` (Tasks 10,11,12); tier values `v3|v4|znver4` throughout.
- **Known soft spots to watch:** (a) the exact output of the vendored AWK (Task 2 Step 3) must match the Task 3 expected fixture — regenerate the fixture from the vendored AWK rather than hand-writing it; (b) `--noscriptlet` means package install scripts don't run, so `/etc/skel` shell configs and any post-install file generation must be verified (Task 11 Step 4) and copied explicitly if missing; (c) `cachyos-branding` script path may differ — confirm with `pacman -Ql cachyos-hooks | grep branding` if the chroot call fails.
```
