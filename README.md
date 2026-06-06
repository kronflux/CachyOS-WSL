# CachyWSL

A [CachyOS](https://cachyos.org/) Linux image for **WSL 2** — the official Arch
Linux WSL build structure, adapted into a professional, well-structured CachyOS
WSL image whose userland is equivalent to a real CachyOS terminal.

> **Status:** Design phase. Implementation not yet started.

## What it produces

- A signed, multi-tier `.wsl` image (x86-64-v3 default, plus v4 and znver4)
  installable via `wsl --install --from-file` or double-click.
- CachyOS identity out of the box: branding, CachyOS repos & `pacman`,
  fish-by-default shell, CachyOS tooling, optimized packages.
- First-class Windows interop (interop, metadata automount, WSLg, Windows-locale
  detection).
- Optional companion: a CachyOS-patched WSL2 kernel (later phase).

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
