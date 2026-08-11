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

**Recommended — add CachyOS to `wsl --install`.** Append it to WSL's distribution
list (the stock online list is preserved) from an **Administrator** PowerShell,
then install by name:

```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss" /v DistributionListUrlAppend /t REG_SZ /d "https://github.com/kronflux/CachyOS-WSL/releases/latest/download/DistributionInfo.json" /f
wsl --install CachyOS
```

Or let the helper handle elevation, WSL 2 setup, and registration for you:

```powershell
irm https://github.com/kronflux/CachyOS-WSL/releases/latest/download/register-distribution.ps1 | iex
```

`irm | iex` runs a fetched script; if you'd rather not, download
[`windows/register-distribution.ps1`](windows/register-distribution.ps1) and run it
directly, or use the `reg add` line above.

**Alternative — install the image file directly** (no registry, WSL 2.4.4+):

```powershell
wsl --install --from-file cachyos-v3-<version>.wsl
```

**Verify the signature** (Cosign keyless):

```bash
cosign verify-blob cachyos-v3-<version>.wsl --bundle cachyos-v3-<version>.wsl.bundle \
  --certificate-identity-regexp 'https://github.com/kronflux/CachyOS-WSL/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

**Testing a local build** (before a release exists): register a freshly-built
`.wsl` with [`windows/register-distribution.ps1`](windows/register-distribution.ps1),
then remove the entry with `-Remove` when done:

```powershell
.\windows\register-distribution.ps1 -Local output\cachyos-v3-<version>.wsl
```

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
# first launch runs the OOBE (detects locale, inits keyring, updates packages, creates your user)
```

`wsl --import` also works but is the legacy path that does **not** run the OOBE —
you'll land at a root shell; run `sudo /usr/lib/wsl/oobe.sh` yourself to finish
setup. To remove a test install: `wsl --unregister CachyOS` (or the name you gave).

## Unattended first-run (scripted deploys)

The OOBE (`/usr/lib/wsl/oobe.sh`) can run without prompts if an optional local
config exists at `/etc/wsl/oobe.conf`. It is purely local — read straight off
disk, no network call, no cloud service, no cloud-init dependency.

Format is `key = value`, one per line, `#` for comments:

```
username = dev
groups = wheel,video,audio
shell = /usr/bin/fish
locale = en-US
run_update = yes
```

| Key | Required | Default | Notes |
| --- | --- | --- | --- |
| `username` | yes (to trigger unattended mode) | — | Validated (lowercase, starts with letter/`_`, max 32 chars, not a system name). An invalid or missing username leaves a root shell for manual setup. |
| `groups` | no | `sys,network,rfkill,users,video,storage,lp,audio,wheel` | Comma-separated; unknown groups are skipped. |
| `shell` | no | `/usr/bin/fish` | Login shell for the created user. |
| `locale` | no | `en-US` | Windows-culture-style locale, mapped to a glibc locale. |
| `run_update` | no | `yes` | `yes`/`no`; the OOBE runs `pacman -Syu --noconfirm` automatically (interactive and unattended alike). Set `no` to skip it. |

When a valid `username` is present, the OOBE creates the user, sets it as the
WSL default user, and applies the other keys with no prompts. The deployer
sets the user's password out-of-band (unattended mode does not prompt for
one) — e.g. via `wsl -d CachyOS -u root -- passwd <user>` after first launch.

To inject the config, register the image without auto-launching it
(`--no-launch`), write the file as root, then launch — the interactive
launch is what triggers the OOBE command:

```powershell
wsl --install --from-file cachyos-v3-<version>.wsl --no-launch
wsl -d CachyOS -u root -- sh -c 'mkdir -p /etc/wsl && cat > /etc/wsl/oobe.conf' < oobe.conf
wsl -d CachyOS   # first interactive launch now runs unattended
```

Alternatively, bake `/etc/wsl/oobe.conf` into a derived image built on top of
this one.

## Documentation

- **Reproducibility & signature verification:** [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)
- **Windows install & terminal helpers:** [`windows/README.md`](windows/README.md)

## Credits & lineage

Built on the structure of the official
[Arch Linux WSL](https://gitlab.archlinux.org/archlinux/archlinux-wsl) project,
adapted for CachyOS using upstream CachyOS sources.

## License

[GPL-3.0](LICENSE).
