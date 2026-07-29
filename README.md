# CachyWSL

A [CachyOS](https://cachyos.org/) Linux image for **WSL 2** — the official Arch
Linux WSL build structure, adapted into a professional, well-structured CachyOS
WSL image whose userland is equivalent to a real CachyOS terminal.

> **Status:** Phase 1 (bootable core) implemented — builds a working v3 image.
> v4/znver4 tiers, CI, signing, and the optional kernel come in later phases.

## What it produces

- A signed, multi-tier `.wsl` image (x86-64-v3 default, plus v4 and znver4)
  installable via `wsl --install --from-file` or double-click.
- CachyOS identity out of the box: branding, CachyOS repos & `pacman`,
  fish-by-default shell, CachyOS tooling, optimized packages.
- First-class Windows interop (interop, metadata automount, WSLg, Windows-locale
  detection).
- Optional companion: a CachyOS-patched WSL2 kernel (later phase).

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
