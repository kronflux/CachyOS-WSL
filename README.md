# CachyWSL

A [CachyOS](https://cachyos.org/) Linux image for **WSL 2**, built on the
structure of the official Arch Linux WSL project. The userland matches a CachyOS
terminal: CachyOS branding, repositories, `pacman`, and the CachyOS default
shell.

> A signed, reproducible `.wsl` image with a CachyOS terminal userland, built
> and published from CI with Cosign keyless signatures.

## What it produces

- A signed x86-64-v3 `.wsl` image installable via `wsl --install --from-file`
  or double-click.
- CachyOS identity out of the box: branding, CachyOS repos & `pacman`,
  fish-by-default shell, CachyOS tooling, optimized packages.
- Windows interop: binary interop, metadata automount, and Windows-locale
  detection at first boot.

