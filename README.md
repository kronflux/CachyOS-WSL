# CachyWSL

A [CachyOS](https://cachyos.org/) Linux image for **WSL 2** — the official Arch
Linux WSL build structure, adapted into a professional, well-structured CachyOS
WSL image whose userland is equivalent to a real CachyOS terminal.

> **Status:** Phases 1–3 complete — multi-tier CachyOS terminal userland with
> signed, reproducible `.wsl` images published via CI (Cosign keyless). The
> optional CachyOS-patched kernel is a later phase.

## What it produces

- A signed, multi-tier `.wsl` image (x86-64-v3 default, plus v4 and znver4)
  installable via `wsl --install --from-file` or double-click.
- CachyOS identity out of the box: branding, CachyOS repos & `pacman`,
  fish-by-default shell, CachyOS tooling, optimized packages.
- First-class Windows interop (interop, metadata automount, WSLg, Windows-locale
  detection).
- Optional companion: a CachyOS-patched WSL2 kernel (later phase).

## Releases & install

CachyWSL ships CPU-optimized tiers per release (GitHub Releases):

| Tier | Distro name | For | Built by |
|------|-------------|-----|----------|
| x86-64-v3 (default) | `CachyOS` | any modern x86-64 CPU (Haswell/Zen1+) | CI (GitHub-hosted) |
| x86-64-v4 | `CachyOS_v4` | AVX-512 CPUs | CI (GitHub-hosted) |
| Zen4 | `CachyOS_Zen4` | AMD Zen 4/5 | Zen4 host (see below) |

> **znver4 is not built in CI.** The build executes target-optimized binaries in
> the chroot, and Zen4 code SIGILLs on GitHub's non-Zen4 runners. Build it on a
> Zen4 machine with `make build TIER=znver4` (or a self-hosted Zen4 runner) and
> attach the result to the release. v3 and v4 build on any GitHub-hosted runner.

Install a tier from a Release (WSL 2.4.4+):

```powershell
wsl --install --from-file cachyos-v3-<version>.wsl
```

**Verify the signature** (Cosign keyless):

```bash
cosign verify-blob cachyos-v3-<version>.wsl --bundle cachyos-v3-<version>.wsl.bundle \
  --certificate-identity-regexp 'https://github.com/kronflux/CachyOS-WSL/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

For **local testing before a release** (register a locally-built `.wsl`), see [`windows/`](windows/) — an elevated PowerShell registry-override helper.

## Build & try it (Phase 1)

Requires a CachyOS or Arch host (WSL is fine) with the build/test toolchain:

```bash
sudo pacman -S --needed bats fakechroot arch-install-scripts shellcheck shfmt jq
git submodule update --init            # bats test helpers

make unit                              # run the bats unit suites
make build TIER=v3                     # -> output/cachyos-v3-<version>.wsl (+ .sha256)
make test  TIER=v3                     # functional checks against the built tree
```

The build is rootless (`fakechroot`/`fakeroot`) and self-contained (vendored
CachyOS repo transforms + mirrorlists under `vendor/`). It produces a
deterministic, ~190 MB `.wsl`.

Try it in WSL (run from a Windows terminal / PowerShell). Use
`--install --from-file` (WSL ≥ 2.4.4) so the first-run OOBE fires:

```powershell
wsl --install --from-file output\cachyos-v3-<version>.wsl
# first launch runs the OOBE (creates your user, detects locale, inits keyring)
```

`wsl --import` also works but is the legacy path that does **not** run the OOBE —
you'll land at a root shell; run `sudo /usr/lib/wsl/oobe.sh` yourself to finish
setup. To remove a test install: `wsl --unregister CachyOS` (or the name you gave).

## Documentation

- **Design specification:** [`docs/superpowers/specs/2026-06-06-cachywsl-design.md`](docs/superpowers/specs/2026-06-06-cachywsl-design.md)
- **Reference project survey:** [`docs/reference-projects-map.md`](docs/reference-projects-map.md)

## Credits & lineage

Built on the structure of the official
[Arch Linux WSL](https://gitlab.archlinux.org/archlinux/archlinux-wsl) project,
adapted for CachyOS using upstream CachyOS sources and informed by the community
CachyOS-WSL efforts (okrc, dwalleck, taalojarvi) and yuk7's ArchWSL.

## License

To be determined (the Arch WSL base is GPL-3.0).
