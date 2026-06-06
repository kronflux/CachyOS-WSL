# CachyWSL — Design Specification

- **Date:** 2026-06-06
- **Status:** Approved design (pre-implementation)
- **Companion doc:** [`docs/reference-projects-map.md`](../../reference-projects-map.md)

## 1. Summary

CachyWSL produces a **CachyOS Linux image for WSL 2** whose userland is
equivalent to a real CachyOS terminal. It is built by **forking the official
Arch Linux WSL project's structure and toolchain** (Makefile + `scripts/*.sh` +
`rootfs/` overlay, `fakechroot`/`fakeroot`, GitLab-grade quality practices) and
**grafting CachyOS specifics** — CachyOS's own optimized repos (`[cachyos-core-<tier>]` etc. served from
`mirror.cachyos.org`, x86-64-v3/v4/znver4), CachyOS `pacman`, keyring,
hooks/branding, and the CachyOS shell
experience — sourced from the authoritative upstream CachyOS packages.

Primary deliverable: a signed, multi-tier `.wsl` image distributed directly via
GitHub Releases with a `DistributionInfo.json` manifest. Optional companion
deliverable (later phase): a CachyOS-patched WSL2 kernel.

### Goals

- A `.wsl` image that installs via `wsl --install --from-file` / double-click and
  feels like CachyOS: branding, fish-by-default shell, CachyOS tooling, optimized
  packages.
- First-class Windows interoperability (interop, metadata automount, WSLg,
  Windows-locale detection).
- Professional engineering: linting, validation, functional tests, deterministic
  packaging, Cosign signing, automated GitHub Actions releases.
- Per-CPU-tier images (x86-64-v3 default, plus v4 and znver4).

### Non-goals (v1)

- Microsoft Store / `microsoft/WSL` official listing (deferred; direct
  distribution first).
- Full bit-for-bit reproducibility à la Arch (infeasible — CachyOS/ALHP repos
  have no dated archive snapshots). We target deterministic packaging instead.
- Desktop/graphical stack, hardware drivers, bootloader/initramfs (irrelevant in
  WSL).
- Bundling the optimized kernel into the rootfs (it ships as a separate artifact).

## 2. Key decisions (locked)

| # | Decision | Choice |
|---|---|---|
| Build engine | rootless, reproducible, no Docker | **Arch `fakechroot`/`fakeroot`** + CachyOS repos injected into build pacman config |
| CPU tiers | optimization identity | **v3 (default) + v4 + znver4** matrix |
| CI/CD | community + Windows-dev parity | **GitHub Actions** + Releases + Dependabot |
| Userland | CachyOS terminal parity | **fish default** (+ zsh + bash), CachyOS config metapackages |
| pacman | hwcaps tiering + fidelity | **ship CachyOS `pacman`** package + its `pacman.conf` (Color/ILoveCandy on) |
| makepkg | distributable images | **tier `-march`** (v3/v4) from CachyOS devtools presets, **not** `-march=native` |
| Repro | realistic target | **deterministic packaging + Cosign-signed checksums** (a) |
| Distribution | community-appropriate | **direct** GitHub Releases + `DistributionInfo.json` (b) |
| Phasing | incremental | **4 phases** (c) |
| Repo setup | reproducible, offline-capable | **vendor + pin** CachyOS repo AWK transforms + mirrorlist pkgs (don't fetch `develop`) |

## 3. Repository layout

```
CachyWSL/
├── Makefile                      # build / test / validate / clean (TZ=UTC, TIER param)
├── scripts/
│   ├── build-image.sh            # core build (Arch flow + CachyOS graft), per-tier
│   ├── inject-cachyos-repos.sh   # vendored cachyos-repo-add-script logic, tier-explicit
│   ├── test-image.sh             # in-chroot functional tests
│   ├── validate-rootfs.sh        # static validation gate (dwalleck 9-layer style)
│   └── exclude                   # tar exclude list (Arch + okrc merged)
├── vendor/
│   ├── cachyos-repo/             # pinned install-repo.awk, install-v4-repo.awk,
│   │   │                         #   install-znver4-repo.awk + checksums
│   │   └── mirrorlists/          # pinned cachyos*-mirrorlist packages (or .conf)
│   └── makepkg/                  # x86_64_v3.conf, x86_64_v4.conf (+ rust.conf)
├── rootfs/                       # overlay merged into image
│   ├── etc/
│   │   ├── wsl.conf
│   │   ├── wsl-distribution.conf
│   │   ├── locale.conf
│   │   └── pacman.d/             # mirrorlist(s)
│   └── usr/lib/wsl/
│       ├── oobe.sh
│       ├── cachyos.ico
│       ├── terminal-profile.json
│       └── 50-setcap-iputils.hook (staged into /etc/pacman.d/hooks)
├── packages/
│   ├── base.list                 # shared userland package set
│   └── tier.d/                   # any tier-specific deltas (usually empty)
├── windows/                      # PowerShell tooling
│   ├── override-manifest.ps1
│   └── setup-terminal.ps1
├── kernel/                       # P4 optional: build.sh (CachyOS WSL2 kernel)
├── .github/
│   ├── workflows/                # ci.yml (lint/validate/build-matrix/test/sign/release)
│   └── dependabot.yml
└── docs/
    ├── reference-projects-map.md
    └── superpowers/specs/2026-06-06-cachywsl-design.md
```

## 4. Build pipeline (`scripts/build-image.sh`)

Invoked per tier: `build-image.sh <TIER> <IMAGE_VERSION>` where
`TIER ∈ {v3, v4, znver4}`. Runs rootless under `fakechroot -- fakeroot`.

1. **Determinism setup:** `export TZ=UTC`; derive `SOURCE_DATE_EPOCH` from
   `IMAGE_VERSION` date.
2. **Prepare pacman env:** neutralize ALPM hooks (symlink each into
   `$BUILDDIR/alpm-hooks/.../dev/null`); seed pacman.conf from a vendored base.
3. **Inject CachyOS repos (`inject-cachyos-repos.sh`, tier-explicit):**
   - Trust CachyOS key `F3B607488DB35A47` (`pacman-key --recv-keys … --keyserver
     keyserver.ubuntu.com` then `--lsign-key`) in the **build** keyring.
   - `pacman -U` the pinned `cachyos-keyring`, `cachyos-mirrorlist`,
     `cachyos-v3-mirrorlist`, `cachyos-v4-mirrorlist`, and CachyOS `pacman` from
     `vendor/` (offline-capable; checksum-verified).
   - Apply the **tier-matching** vendored AWK transform (`install-repo.awk` for
     v3, `install-v4-repo.awk` for v4, `install-znver4-repo.awk` for znver4) to
     produce the build `pacman.conf` with stanzas `[cachyos-<tier>]`,
     `[cachyos-core-<tier>]`, `[cachyos-extra-<tier>]`, `[cachyos]` and
     `Architecture = auto`. **Do not autodetect** the CPU tier (cross-build).
4. **Overlay `rootfs/`** into `$BUILDDIR`; symlink `/etc/os-release` →
   `/usr/lib/os-release`.
5. **Install packages:** `fakechroot -- fakeroot -- pacman -Sy -r "$BUILDDIR"
   --config <build pacman.conf> --noscriptlet --hookdir <neutralized> <set>` where
   `<set>` = contents of `packages/base.list` (see §7).
6. **Post-install system config (chroot):**
   - `update-ca-trust`; `systemd-sysusers`.
   - Run `cachyos-branding` so `/etc/os-release`, `/etc/lsb-release`, `/etc/issue`
     identify as CachyOS.
   - Install vendored tier `makepkg.conf` to `/etc/makepkg.conf`; enable
     `Color`/`ILoveCandy` in `/etc/pacman.conf`.
   - `%wheel` sudoers drop-in (`/etc/sudoers.d/10-wheel`).
   - `chsh`-equivalent: set fish as the skel/default shell (via OOBE useradd `-s`).
7. **WSL hardening:**
   - Mask `systemd-firstboot`, `console-getty`, `getty@`, `serial-getty@`
     (Hyper-V shared-TTY, WSL#13595) and the WSL-incompatible units
     (`systemd-resolved`, `systemd-networkd`, `NetworkManager`,
     `systemd-tmpfiles-*`, `tmp.mount`, etc.).
   - Remove/disable WSL-irrelevant CachyOS hooks:
     `cachyos-plymouth-initramfs.hook` (no initramfs) and
     `cachyos-reboot-required.hook` (needs graphical D-Bus). Keep branding hooks.
   - Install `50-setcap-iputils.hook` + apply `cap_net_raw+p` to `ping`.
8. **Cleanup + deterministic pack:**
   - Clear `etc/pacman.d/gnupg/*` (regenerated at OOBE); apply `scripts/exclude`.
   - Normalize mtimes to `SOURCE_DATE_EPOCH`.
   - `fakeroot -- tar --numeric-owner --xattrs --acls --mtime=@$SOURCE_DATE_EPOCH
     --clamp-mtime --sort=name --pax-option=delete=atime,delete=ctime
     --exclude-from=scripts/exclude -C "$BUILDDIR" -c .` → `xz -9 -T0` →
     `cachyos-<tier>-<version>.wsl` → `sha256sum`.

## 5. WSL integration & branding (`rootfs/`)

### `etc/wsl.conf`
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

### `etc/wsl-distribution.conf`
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

All WSL files live under `/usr/lib/wsl/` (`0644` configs, `0755` scripts). The
terminal profile template omits `name`/`commandLine` (WSL auto-generates them).
`locale.conf` defaults to `LANG=C.UTF-8` (overridden by OOBE locale detection).

### `usr/lib/wsl/oobe.sh` (first-run, idempotent)
1. Detect Windows locale via PowerShell `(Get-Culture).Name`, map to
   `xx_XX.UTF-8`, enable in `/etc/locale.gen`, `locale-gen`, `localectl
   set-locale` (fallback `en_US.UTF-8`).
2. `pacman-key --init && pacman-key --populate archlinux cachyos`.
3. Prompt for username; `useradd -m -u 1000 -G wheel,… -s /usr/bin/fish`;
   `passwd`.
4. Write `[user] default=<name>` to `/etc/wsl.conf`.
5. WSLg: export `XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir` in shell profile; `cd ~`
   when launched from `/mnt/*`.
6. Print CachyOS welcome + `pacman -Syu` recommendation.

### Branding
`cachyos.ico` (from `CachyOS_repos` assets) + `terminal-profile.json` (CachyOS
color scheme, CaskaydiaCove/Fantasque Nerd Font, acrylic). `os-release` branding
comes from the `cachyos-branding` hook at build time.

## 6. CPU tiers & publishing

Build matrix emits `cachyos-{v3,v4,znver4}-<version>.wsl` + `.sha256` + Cosign
`.bundle`. A generated `DistributionInfo.json` (`ModernDistributions.CachyOS[]`,
v3 `Default:true`) points `Amd64Url` at the GitHub Release asset URLs with
SHA256. Users install via double-click, `wsl --install --from-file`, or the
manifest-override flow (see §9 `override-manifest.ps1`).

`IMAGE_VERSION` format: `YYYY.MM.DD` (+ CI run number for uniqueness), matching
the Arch convention.

## 7. Userland (CachyOS terminal parity, WSL-lean)

`packages/base.list` (curated from the CLI-ISO/netinstall analysis — excludes all
live/boot/xorg/firmware/VM-guest packages):

- **Core:** `base sudo iptables-nft openssh git vim nano man-db man-pages
  bash-completion`
- **CachyOS identity:** CachyOS `pacman`, `cachyos-keyring cachyos-mirrorlist
  cachyos-v3-mirrorlist cachyos-hooks cachyos-settings cachyos-rate-mirrors`
  (optimized packages come from CachyOS's own `[cachyos-core-<tier>]` repos —
  **not** ALHP. ALHP (`alhp-keyring alhp-mirrorlist`) is an optional add-on,
  off by default, evaluated in P2.)
- **Shell experience (pulls deps transitively):** `cachyos-fish-config`
  (→ fish, fisher, fish-pure-prompt, fish-autopair, eza, bat, fzf, fastfetch,
  tealdeer, expac, pkgfile, ttf nerd font) + `cachyos-zsh-config`
  (→ zsh, oh-my-zsh-git, powerlevel10k, zsh-* plugins) + `bash`
- **Pkg tooling:** `pacman-contrib pkgfile paru`

`/etc/skel` is populated automatically by the config packages, so new OOBE users
inherit the full experience. **fish** is the default login shell.

**`cachyos-settings` review:** keep its sysctl/performance defaults (WSL-relevant);
its udev/modprobe rules are harmless no-ops in WSL. Validate during P2 that none
of its drop-ins break WSL boot.

**EXCLUDE list (documented):** grub, mkinitcpio*, linux*, linux-firmware*, xorg*,
mesa (unless WSLg GPU needed), plymouth, calamares/installer, partitioning/RAID,
qemu/vmware/vbox guest agents, accessibility firmware, broadcom/ipw firmware.

## 8. Reproducibility & signing

- **Deterministic packaging:** `TZ=UTC`, `SOURCE_DATE_EPOCH`, normalized mtimes,
  `--sort=name --clamp-mtime`, PAX atime/ctime stripped, `--numeric-owner`.
- **Pinned inputs:** vendored, checksum-verified CachyOS repo AWK transforms +
  mirrorlist/keyring/pacman packages (no live `develop`-branch fetches).
- **Signing:** Cosign **keyless** via GitHub Actions OIDC; publish `.wsl`,
  `.sha256`, `.bundle`. Verify documented in README.
- **Caveat (documented):** rolling CachyOS/ALHP repos lack dated snapshots, so two
  builds days apart will differ in package versions — expected. Within a single
  package set, packaging is deterministic.

## 9. Validation & testing (pyramid)

1. **Static (`validate-rootfs.sh`, CI gate):** required files present; perms
   (`0644`/`0755`); `wsl.conf`/`wsl-distribution.conf` content; `terminal-profile.
   json` valid JSON (jq); prohibited files absent (no `resolv.conf`,
   `machine-id`, kernels, initramfs); systemd masking applied; `passwd`/`shadow`
   sane (no hashes); icon < 10 MB; pacman.conf repos correct.
2. **Functional (`test-image.sh`, in-chroot):** `pacman-key --init/--populate`;
   `pacman -Sy`; install a probe package; locale UTF-8; fish present & default;
   `cachyos-*` repos resolve.
3. **Integration (scheduled, WSL-on-Windows):** import each tier, run OOBE,
   `pacman -Syu`, interop (`cmd.exe`), metadata perms, WSLg env. Plus optional
   manual validation against a real CachyOS reference (SSH/VM) for `/etc/skel`,
   `cachyos-settings`, and live `pacman -Syu` resolution.

### Windows tooling (`windows/`)
- `override-manifest.ps1`: register a local `.wsl` via the
  `HKLM:\…\Lxss\DistributionListUrl` registry override (non-destructive) for
  testing without publishing.
- `setup-terminal.ps1`: merge the CachyOS profile into Windows Terminal
  `settings.json`.

## 10. CI/CD (GitHub Actions)

`ci.yml` stages: **lint** (shellcheck, markdownlint, codespell) → **validate**
(`validate-rootfs.sh`) → **build matrix** (`v3`/`v4`/`znver4`) → **test**
(functional + `microsoft/WSL` `validate-modern.py`) → **sign** (Cosign keyless,
OIDC) → **release** (GitHub Release + `DistributionInfo.json`). Triggers: push to
`main`, manual dispatch, weekly schedule. `dependabot.yml` tracks
`github-actions`. Build matrix runs on Arch-based runners (container with
`devtools fakechroot fakeroot`).

## 11. Optional kernel (Phase 4)

Standalone `kernel/build.sh` (taalojarvi-style, validated minimal subset):
- Shallow-clone `microsoft/WSL2-Linux-Kernel` (current `linux-msft-wsl-*`).
- Apply 3 pinned CachyOS patches: `0001-cachyos-base-all`, `0001-clang-polly`,
  `0001-bore-cachy`.
- Config: `SCHED_BORE`, `CC_OPTIMIZE_FOR_PERFORMANCE_O3`, `HZ_300`,
  `TRANSPARENT_HUGEPAGE_ALWAYS`, `PREEMPT`, thin LTO, `LOCALVERSION=-cachy-wsl2`,
  drop `DEBUG_INFO`.
- Build `LLVM=1 LD=ld.lld KCFLAGS="-O3 -mllvm -polly"`.
- Output `bzImage` + modules + README → separate GitHub Release asset for
  `.wslconfig` (`[wsl2] kernel=…`). **Not** in the rootfs critical path.

## 12. Phasing

- **P1 — Bootable core:** repo skeleton, `build-image.sh` (v3), repo injection,
  `rootfs/` (wsl.conf, wsl-distribution.conf, oobe.sh, branding), minimal
  userland → image that imports, runs OOBE, boots to a CachyOS-branded fish
  shell.
- **P2 — Parity & validation:** full userland (`base.list`), `cachyos-settings`
  review, `validate-rootfs.sh` + `test-image.sh`, v4 + znver4 tiers.
- **P3 — Release engineering:** GitHub Actions pipeline, Cosign signing,
  `DistributionInfo.json`, Windows PowerShell tooling, README/docs.
- **P4 — Optional kernel:** `kernel/build.sh` + its release flow.

## 13. Open items to confirm during implementation

- Exact pinned versions for vendored CachyOS keyring/mirrorlist/pacman/AWK and
  the kernel patches (record checksums in `vendor/`).
- Whether `mesa`/WSLg GPU packages are wanted by default (currently excluded;
  add if GUI-app parity is desired).
- Final `cachyos-settings` drop-in allow/deny list after the P2 WSL review.
- Runner image choice for GitHub Actions (Arch container vs custom).
