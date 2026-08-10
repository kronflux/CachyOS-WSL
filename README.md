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

## Releases & install

Each release (GitHub Releases) ships one image optimized for **x86-64-v3** — every
modern x86-64 CPU (Intel Haswell / AMD Zen 1 and newer). It installs as the
`CachyOS` distribution.

Higher microarchitecture levels (x86-64-v4/AVX-512, Zen4) are intentionally not
shipped: they exclude most current consumer CPUs (Intel dropped AVX-512 from 12th-gen
Core onward) while giving a terminal userland no measurable benefit.

Install it from a Release (WSL 2.4.4+):

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

## Build & try it

Requires a CachyOS or Arch host (WSL is fine) with the build/test toolchain:

```bash
sudo pacman -S --needed bats fakechroot arch-install-scripts shellcheck shfmt jq
git submodule update --init            # bats test helpers

make unit                              # run the bats unit suites
make build                             # -> output/cachyos-v3-<version>.wsl (+ .sha256)
make test                              # functional checks against the built tree
```

The build is rootless (`fakechroot`/`fakeroot`) and self-contained (vendored
CachyOS repo transforms + mirrorlists under `vendor/`). It produces a
deterministic, ~310 MB `.wsl`.

Try it in WSL (run from a Windows terminal / PowerShell). Use
`--install --from-file` (WSL ≥ 2.4.4) so the first-run OOBE fires:

```powershell
wsl --install --from-file output\cachyos-v3-<version>.wsl
# first launch runs the OOBE (creates your user, detects locale, inits keyring)
```

`wsl --import` also works but is the legacy path that does **not** run the OOBE —
you'll land at a root shell; run `sudo /usr/lib/wsl/oobe.sh` yourself to finish
setup. To remove a test install: `wsl --unregister CachyOS` (or the name you gave).

