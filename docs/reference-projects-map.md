# CachyWSL — Reference Project Map

> Survey of the six reference projects in this workspace, documenting purpose,
> architecture, features, pros/cons, and what CachyWSL should adopt from each.
> CachyWSL = the official Arch Linux WSL structure, adapted into a professional,
> well-structured CachyOS WSL image (userland ≈ a real CachyOS terminal), with
> optional optimized kernel, Windows-side tooling, and full CI/CD + signing.

## Critical finding (reframes the premise)

A byte-for-byte diff of `cachyos-wsl-CachyOS` against `archlinux-wsl-archlinux`
shows the "semi-official CachyOS WSL project" **is not actually customized for
CachyOS**. It is a lightly-modified, slightly *older* fork of the official Arch
WSL repo:

- Still titled "Arch Linux WSL Image", still ships `archlinux.ico`, still uses
  the `archlinux` repos.
- **No** CachyOS keyring, **no** CachyOS/ALHP/Chaotic repos, **no** x86-64-v3/v4
  optimization, **no** branding, **no** shell theming.
- It has actually *removed* machinery the official Arch project now has:
  reproducible builds (`TZ=UTC`, `SOURCE_DATE_EPOCH`, archive snapshot pinning,
  sorted/clamped tar, normalized mtimes), `REPRO.md` + `repro-image.sh`, the
  Hyper-V getty masking fix, and keyring clearing.
- Its only real deltas: a different mirror list (rackspace/leaseweb) and a
  thinner `first-setup.sh`.

**Implication:** real CachyOS adaptations live in the *community* projects
(okrc, dwalleck, taalojarvi) and in upstream CachyOS proper — **not** in
`cachyos-wsl-CachyOS`. CachyWSL = official Arch WSL base + CachyOS specifics
grafted from the community forks. `cachyos-wsl-CachyOS` is superseded.

## At a glance

| Project | Type | Build approach | CI | CachyOS-specific? | Standout strength |
|---|---|---|---|---|---|
| **archlinux-wsl-archlinux** | Official Arch rootfs/image | `fakechroot`+`fakeroot`, no container | GitLab CI | No (it's the base) | Reproducible builds, Cosign signing, MS-WSL PR automation, tests |
| **cachyos-wsl-CachyOS** | "Semi-official" fork | Same as Arch (older) | GitLab CI | No — basically vanilla Arch | Nothing unique; a stale base copy |
| **ArchWSL-FS-yuk7** | Mature community rootfs | Makefile + chroot, sentinel files | — | No (Arch) | Battle-tested: 2-stage pacman sig, setcap-ping hook, metadata automount |
| **CachyOS-WSL-okrc** | CachyOS rootfs (real) | Docker `cachyos/cachyos` + script | GitHub Actions + Dependabot | Yes | ALHP v3/v4/znver4 tiering, Chaotic-AUR, OOBE locale detection, DistributionInfo.json |
| **cachyos-wsl-dwalleck** | CachyOS rootfs (real, elaborate) | Makefile + Docker | GitHub Actions (documented) | Yes | Deep research docs, 9-layer validation, PowerShell test tooling, fish/zsh, terminal branding |
| **CachyOS-WSL-taalojarvi** | CachyOS **kernel** only | Single `build.sh` | GitHub Actions | Yes (kernel) | BORE+Polly+O3 LLVM kernel; not a rootfs |

## Per-project profiles

### 1. archlinux-wsl-archlinux — official, gold-standard base

- **Purpose:** Official monthly Arch Linux `.wsl` image; minimal `base`-only
  rootfs with systemd.
- **Build (`scripts/build-image.sh`):** neutralize ALPM hooks (symlink to
  `/dev/null`), devtools pacman.conf, overlay `rootfs/`, pin
  `archive.archlinux.org/repos/<snapshot>` mirror for reproducibility,
  `fakechroot -- fakeroot -- pacman -Sy -r $BUILDDIR base` (no root, no Docker),
  `--noscriptlet`, then update-ca-trust / pacman-key init+populate /
  systemd-sysusers / mask `systemd-firstboot console-getty`, mask `getty@` &
  `serial-getty@` (Hyper-V shared TTY fix, WSL#13595), clear gnupg, normalize
  mtimes to `SOURCE_DATE_EPOCH`, `fakeroot tar --numeric-owner --sort=name
  --clamp-mtime --pax-option=delete=atime,delete=ctime`, `xz -9 -T0`, rename
  `.wsl`, sha256.
- **rootfs/:** `etc/wsl.conf` (`[boot] systemd=true`), `etc/wsl-distribution.conf`
  (oobe command, defaultName, icon), `etc/locale.conf` (`LANG=C.UTF-8`),
  `etc/pacman.d/mirrorlist`, `usr/lib/wsl/first-setup.sh` (welcome + keyring),
  `usr/lib/wsl/archlinux.ico`.
- **CI (GitLab):** lint (shellcheck/markdownlint/codespell) → build → **repro**
  (rebuild + diffoscope) → test (`validate-modern.py` from microsoft/WSL, pacman,
  locale, podman) → **Cosign keyless sign (OIDC)** → upload → auto-PR updating
  `DistributionInfo.json` in microsoft/WSL.
- **Pros:** reproducible, signed, minimal, well-tested, official upstream path.
  **Cons:** WSL2-only, minimal base (no dev tools), keyring regenerated on first
  launch.
- **Adopt:** the entire skeleton + reproducibility + signing + CI + MS-WSL PR.

### 2. cachyos-wsl-CachyOS — stale vanilla fork

- See Critical finding. Effectively un-customized, older Arch. **Adopt: nothing;
  supersede it.** Value is only as evidence of CachyOS's starting point.

### 3. ArchWSL-FS-yuk7 — mature pragmatic patterns

- **Purpose:** Popular community ArchWSL filesystem (yuk7), 2017–2026, MIT.
- **Build (Makefile):** bootstrap from official Arch tarball → chroot → install
  `archlinux-keyring base less nano sudo vim curl` → cleanup → pack; resumable
  via sentinel `.tmp` files; error-tolerant unmounts.
- **Key techniques:**
  - **Two-stage pacman signatures:** `pacman.conf.nosig` (`SigLevel=Never`) for
    bootstrap before keyring exists, then swap to `pacman.conf`
    (`SigLevel=Required DatabaseOptional`). Solves the chicken-and-egg.
  - **`setcap-iputils.hook`:** PostTransaction `setcap cap_net_raw+p
    /usr/bin/ping` so non-root `ping` works (setuid unreliable on NTFS).
  - **`wsl.conf`:** `[automount] options="metadata"` (critical — else Windows
    drives are all 0777), `mountFsTab=true`, `systemd=true`.
  - resolv.conf "magic comment" so WSL regenerates DNS; remove machine-id &
    firstboot service; aggressive cache cleanup.
- **Cons:** hard-coded bootstrap URL/mirrorlist, x86_64-only, no repro/signing.
- **Adopt:** metadata automount, setcap-ping hook, 2-stage signature bootstrap,
  cleanup list, resolv.conf marker.

### 4. CachyOS-WSL-okrc — cleanest real CachyOS rootfs

- **Build (`scripts/rootfs-gen.sh` in `cachyos/cachyos` Docker):** 6 functions —
  configure_pacman / setup_rootfs / install_packages / configure_system /
  mask_services / pack_rootfs. Per-variant `OPTION=v3|v4|znver4`.
- **CachyOS specifics:**
  - Dynamic repo injection via fetched AWK scripts (`install-repo.awk`,
    `install-v4-repo.awk`, `install-znver4-repo.awk`) from CachyOS GitHub.
  - Rewrite `[core]`→`[core-x86-64-v3]` (or v4) + ALHP mirrorlist for optimized
    packages; add Chaotic-AUR (`chaotic-keyring`, `chaotic-mirrorlist`).
  - `BASE_PACKAGES="base cachyos-hooks cachyos-keyring cachyos-mirrorlist
    iptables-nft sudo alhp-keyring alhp-mirrorlist"`.
  - Mask 14 systemd units (resolved, networkd, NetworkManager, getty.target,
    homed, userdbd, firstboot, nsresourced, tmpfiles set, tmp.mount).
  - pacman color + "ILoveCandy"; `%wheel` sudoers.
- **OOBE (`oobe.sh`):** detect Windows locale via PowerShell `(Get-Culture).Name`
  → locale-gen; `pacman-key --init && --populate archlinux cachyos alhp`; create
  UID-1000 user with full group set.
- **wsl-distribution.conf:** oobe command, `defaultUid=1000`, `defaultName=CachyOS`.
  Terminal profile: "Tomorrow Night Blue", acrylic.
- **CI (GitHub Actions, self-hosted, weekly):** `make` → sha256 → build
  `DistributionInfo.json` → GitHub Release (date tag). Dependabot (Actions only).
- **Cons:** self-hosted runner; repo AWK scripts unpinned (develop branch); no
  signing; thin tests; znver4 reuses v4 mirrorlist.
- **Adopt:** ALHP tiering, repo+keyring setup, OOBE locale+user, exclude list,
  DistributionInfo.json generation.

### 5. cachyos-wsl-dwalleck — research goldmine

- **Purpose:** Most documented community CachyOS WSL effort; modern `.wsl` format.
- **Build:** Makefile → `build-rootfs.sh` (Docker) → `cleanup.sh` → `validate.sh`
  → tar/xz + SHA256/512. Variants v3/v4/znver4. Two mirrorlists to handle
  `$arch` vs `$arch_v3` substitution.
- **`validate.sh` (9 layers):** config existence, permissions, wsl.conf content,
  JSON validity (jq), prohibited files (no resolv.conf/machine-id/kernels),
  systemd masking, system files (passwd/shadow, no hashes), size checks, pacman
  config. Exit 0/1 for CI gating.
- **OOBE (`oobe.sh`):** username prompt, UID-1000 + wheel, sudoers, keyring init,
  Windows-locale detection+map, bashrc `cd ~` when launched from `/mnt/*`, WSLg
  `XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir`, write `[user]` to wsl.conf.
- **Userland:** fish (default) + zsh (p10k) + bash; `bat eza fzf fastfetch
  tealdeer expac pkgfile yay`; Nerd Fonts; `iptables-nft`, `jq`, `openssh`.
- **Windows tooling:** `override-manifest.ps1` (registry `DistributionListUrl`
  override → test local `.wsl` without publishing; non-destructive),
  `setup-terminal.ps1` (merge CachyOS profile into Windows Terminal settings).
- **Research docs (concrete conclusions):** store WSL files in `/usr/lib/wsl/`
  (`0644` conf, `0755` scripts); profile template must omit `name`/`commandLine`;
  branding = emerald `#2E7D32` + Nord, CaskaydiaCove Nerd Font, acrylic 0.9;
  direct `.wsl` distribution beats Store for community projects (Store =
  `wslpartners@microsoft.com`, $19, 2–4 wk); WSLg via env vars is enough for most;
  testing pyramid (static → container → WSL-on-Windows → health check).
- **Cons:** docs ahead of implementation in places; no signing; Docker dependency.
- **Adopt:** validation framework, local-test PowerShell tooling, research
  conclusions, shell + terminal UX, testing pyramid.

### 6. CachyOS-WSL-taalojarvi — kernel only (optional companion)

- **Purpose:** Build a CachyOS-patched WSL2 kernel; not a rootfs.
- **`build.sh` (single script, 7 stages):** apt deps (clang/lld/llvm) → shallow
  clone `microsoft/WSL2-Linux-Kernel` (6.18.y) → fetch CachyOS patches
  (cachyos-base-all, clang-polly, bore-cachy) → `git am --3way` → config (BORE,
  POLLY, no DEBUG_INFO, `LOCALVERSION=-cachy-wsl2`) → build `LLVM=1 LD=ld.lld
  KCFLAGS="-O3 -mllvm -polly"` → package bzImage + modules + README.
- **Use:** `.wslconfig` `[wsl2] kernel=C:\bzImage`. No rootfs/OOBE/branding.
- **Cons:** no caching, unpinned patch sources, manual install.
- **Adopt:** only if shipping an optional optimized kernel; clean stage structure
  and env-overridable config are good references.

## Adoption menu (what CachyWSL pulls from where)

- **Structure / quality / reproducibility / signing / CI / MS-WSL publishing** →
  official Arch (`archlinux-wsl-archlinux`)
- **CachyOS repos, keyring, ALHP v3/v4/znver4, Chaotic-AUR, DistributionInfo.json**
  → okrc
- **Research-backed OOBE, validation, local PowerShell testing, shell + terminal
  branding, testing pyramid** → dwalleck
- **Metadata automount, setcap-ping, 2-stage signature bootstrap, cleanup,
  resolv.conf marker** → yuk7
- **Optional optimized kernel** → taalojarvi
- **True package/userland parity** → upstream CachyOS proper (beyond these forks)

## Key open design decisions (to resolve in the spec)

1. Build engine: official Arch `fakechroot`/`fakeroot` (reproducible, no Docker)
   vs `cachyos/cachyos` Docker (simpler for CachyOS repos/keyring).
2. CPU optimization tiers: single x86-64-v3 vs v3/v4/znver4 matrix.
3. Userland richness: minimal base + CachyOS configs vs full "CachyOS terminal"
   (fish default + bat/eza/fzf/fastfetch + cachyos-fish/zsh-config).
4. CI platform: GitLab (Arch parity) vs GitHub Actions (community parity, user's
   environment).
5. Signing/reproducibility: keep Cosign keyless + archive snapshot pinning?
6. Kernel: ship optional optimized kernel or rootfs-only v1.
