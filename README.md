# CachyWSL

[![Build](https://github.com/kronflux/CachyOS-WSL/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/kronflux/CachyOS-WSL/actions/workflows/build.yml)

An unofficial [CachyOS](https://cachyos.org/) image for [WSL](https://github.com/microsoft/WSL) 2 (or above), built on the
structure of the [Arch Linux WSL image](https://gitlab.archlinux.org/archlinux/archlinux-wsl).
The image runs on any x86-64 CPU, and its first-run setup switches to the
CachyOS packages optimized for the CPU.

This project is not affiliated with CachyOS. CachyOS publishes its own official
WSL image at [CachyOS/cachyos-wsl](https://github.com/CachyOS/cachyos-wsl).

## Features

- **CPU-optimized packages.** Like the CachyOS installer, first-run setup detects
  the CPU and switches to the `znver4`, `x86-64-v4` or `x86-64-v3` repositories.
  CPUs without x86-64-v3 keep the generic packages.
- **A CachyOS terminal.** CachyOS branding, repositories, settings and `pacman`,
  fish as the default shell with zsh also configured, and developer, CLI and
  network tools. See [What's included](#whats-included).
- **Guided first-run setup.** It detects the Windows locale, ranks mirrors,
  updates the system and creates your user. It resumes if interrupted and can run
  unattended from a config file.
- **WSL integration.** Windows interop survives `systemd-binfmt`, the systemd user
  session retries when WSL starts it too early, `ping` works without root, and
  Windows Terminal gets a CachyOS profile and color scheme.
- **Signed releases**, built and published monthly and on every tag.

## What's included

The image installs the `base` system and the packages listed in [`packages/base.list`](packages/base.list)
and their dependencies:

| Group | Packages |
| --- | --- |
| CachyOS system | `cachyos-settings` (sysctl, transparent huge page, systemd and journald tuning), `cachyos-hooks` (pacman hooks), `cachyos-rate-mirrors` (ranks the mirrors at first launch and weekly), `archlinux-keyring`, `cachyos-keyring`, `cachyos-mirrorlist`, `cachyos-v3-mirrorlist`, `cachyos-v4-mirrorlist`, the CachyOS build of `pacman`, and `zlib-ng-compat` in place of `zlib` |
| Shells | `fish` with `cachyos-fish-config` (pure prompt, fisher, autopair, `eza`, `bat`, `fzf`, `fastfetch`, `tealdeer`), `zsh` with `cachyos-zsh-config` (oh-my-zsh, powerlevel10k, autosuggestions, syntax highlighting), `bash-completion` |
| Administration and development | `sudo` (members of `wheel`, with a password), `base-devel`, `git`, `python`, `perl`, `openssh` |
| Editors | `vim`, `nano` with `nano-syntax-highlighting`, `micro` with `cachyos-micro-settings` |
| CLI tools | `btop`, `duf`, `ripgrep`, `fd`, `inxi`, `plocate`, `pv`, `tmux`, `lsof`, `less`, `man-db`, `man-pages`, `unzip`, `unrar`, `s-nail`, `diffutils`, `e2fsprogs`, `logrotate`, `lsb-release` |
| Networking | `wget`, `rsync`, `bind` (`dig`, `nslookup`), `inetutils`, `openbsd-netcat`, `iptables-nft`, `ufw` with `ufw-extras` (installed, not enabled) |
| Package tools | `pacman-contrib` (`paccache`, `checkupdates`), `pkgfile`, `reflector`, `rebuild-detector`, `cachy-update` (update notifier; its tray applet and timer are disabled) |

Parts of the CachyOS packages that have no use in WSL are disabled: zram swap
(WSL manages swap), the Plymouth and reboot-required pacman hooks, and the PCI
latency and wireless regulatory domain services.

## How this differs from the official [CachyOS image](https://github.com/CachyOS/cachyos-wsl)

Both images are generic and switch to the CPU-optimized repositories on first
launch.

| | CachyWSL | Official CachyOS WSL image |
| --- | --- | --- |
| Packages | Base system, the CachyOS settings, hooks and mirror tools, fish and zsh, developer, CLI and network tools | Base system, `sudo`, the CachyOS settings, hooks and mirror tools, and fish |
| First-run setup | Locale detection, mirror ranking, CPU optimization, update, user creation, unattended mode | Mirror ranking, CPU optimization, user creation |
| Windows Terminal | CachyOS color scheme and font | Default profile |
| WSL fixes | Interop re-registration, user-session retry, `ping` without root | Not included |
| `/tmp` | tmpfs, cleaned at boot | On disk |
| Maintained by | The community ([kronflux](https://github.com/kronflux)) | The CachyOS team |

## Installation

Requires Windows with [WSL 2](https://learn.microsoft.com/en-us/windows/wsl/install) or above.
WSL 1 is not supported.

### Install by name (recommended)

Add CachyOS to the WSL distribution list (Microsoft's online list stays
available) from an **Administrator** PowerShell, then install it by name:

```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss" /v DistributionListUrlAppend /t REG_SZ /d "https://github.com/kronflux/CachyOS-WSL/releases/latest/download/DistributionInfo.json" /f
wsl --install CachyOS
```

Or let the helper elevate itself, set up WSL, register the list and install:

```powershell
irm https://github.com/kronflux/CachyOS-WSL/releases/latest/download/register-distribution.ps1 | iex
```

`irm | iex` runs a downloaded script. To read it first, download
[`windows/register-distribution.ps1`](windows/register-distribution.ps1) and run
it directly. The `DistributionListUrlAppend` value holds one URL per machine;
the helper stops without changing it when another tool already uses it. See
[`windows/README.md`](windows/README.md) for its options.

### Install the image file (WSL 2.4.4 or later)

Download the [latest `.wsl` image](https://github.com/kronflux/CachyOS-WSL/releases/latest)
and double-click it, or run:

```powershell
wsl --install --from-file cachyos-<version>.wsl
```

### Install on WSL older than 2.4.4

`wsl --import` does not run first-run setup, so run it yourself, then restart
the distribution to log in as the user it created:

```powershell
wsl --import CachyOS C:\Users\<Username>\WSL\CachyOS C:\Users\<Username>\Downloads\cachyos-<version>.wsl
wsl -d CachyOS -u root -- /usr/lib/wsl/first-setup.sh
wsl --terminate CachyOS
wsl -d CachyOS
```

### Verify the signature

Each release ships a Cosign keyless signature bundle next to the image:

```bash
cosign verify-blob cachyos-<version>.wsl --bundle cachyos-<version>.wsl.bundle \
  --certificate-identity-regexp '^https://github\.com/kronflux/CachyOS-WSL/\.github/workflows/release\.yml@refs/(heads/main|tags/20[0-9.]+)$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## First launch

The first launch runs the setup in `/usr/lib/wsl/first-setup.sh`:

1. Configure the locale from the Windows display language.
2. Initialize the pacman keyring.
3. Rank the mirrors.
4. Switch to the repositories optimized for the CPU and reinstall the packages
   from them.
5. Update the system.
6. Create your user account, with fish as its shell and `sudo` through `wheel`.

The first launch takes longer than a plain install, because step 4 downloads
the optimized packages. If setup is interrupted, or no user account is created,
it runs again on the next launch and continues where it stopped.

CachyOS is a rolling release: run `sudo pacman -Syu` regularly. Report problems
at [github.com/kronflux/CachyOS-WSL/issues](https://github.com/kronflux/CachyOS-WSL/issues).

## Unattended setup

Setup runs without prompts when `/etc/wsl/oobe.conf` exists with a `username`.
The file is read from disk only, with no network or cloud-init involved. The
format is `key = value`, one per line, with `#` for comments:

```ini
username = dev
groups = wheel,video,audio
shell = /usr/bin/fish
locale = en-US
run_update = yes
optimize = yes
```

| Key | Required | Default | Notes |
| --- | --- | --- | --- |
| `username` | Yes, to run unattended | None | Lowercase, starts with a letter or `_`, at most 32 characters, not a system account. An invalid name leaves a root shell for manual setup. |
| `groups` | No | `sys,network,rfkill,users,video,storage,lp,audio,wheel` | Comma-separated; groups that do not exist are skipped. |
| `shell` | No | `/usr/bin/fish` | Login shell of the user. |
| `locale` | No | `en-US` | A Windows culture name, mapped to a glibc locale. |
| `run_update` | No | `yes` | `no` skips `pacman -Syu`. |
| `optimize` | No | `yes` | `no` keeps the generic packages; run `/usr/lib/wsl/optimize-repos` as root later to switch. |

Unattended setup does not set a password. Set it afterwards with
`wsl -d CachyOS -u root -- passwd <user>`.

To provide the file, install the image without launching it, write the file as
root, then launch it:

```powershell
wsl --install --from-file cachyos-<version>.wsl --no-launch
wsl -d CachyOS -u root -- sh -c 'mkdir -p /etc/wsl && cat > /etc/wsl/oobe.conf' < oobe.conf
wsl -d CachyOS
```

## Windows Terminal theme

Installing the image creates a Windows Terminal profile with the CachyOS color
scheme. To apply the scheme to an existing CachyOS profile, run
[`windows/setup-terminal.ps1`](windows/setup-terminal.ps1); it backs up
`settings.json` before writing.

## Building from source

The build runs without root on a CachyOS or Arch Linux host, including one in
WSL. It needs these packages:

```bash
sudo pacman -S --needed make git fakechroot fakeroot jq python bats bats-support bats-assert shellcheck
```

The host keyring must trust the CachyOS signing key, which it does on CachyOS.
On Arch Linux, add it:

```bash
sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver hkps://keyserver.ubuntu.com
sudo pacman-key --lsign-key F3B607488DB35A47
```

| Command | What it does |
| --- | --- |
| `make build` | Builds `output/cachyos-<version>.wsl` and its `.sha256`. `IMAGE_VERSION` sets the version, by default today's date. |
| `make validate` | Checks the built tree for the required files and settings. |
| `make test` | Runs functional checks inside the built tree. |
| `make validate-microsoft` | Runs Microsoft's WSL image validator on the built image (needs network access). |
| `make unit` | Runs the bats unit tests. |
| `make lint` | Runs shellcheck on the scripts. |
| `make clean` | Removes the build output and the build tree. |

The build tree lives in `CACHYWSL_WORKDIR`, by default `/var/tmp/cachywsl`. Keep
it on a Linux filesystem: `/mnt/c` cannot store Unix permissions, which breaks
`sudo` in the image.

To try a build, install it with `wsl --install --from-file output\cachyos-<version>.wsl`,
or with `.\windows\register-distribution.ps1 -Local output\cachyos-<version>.wsl`.
Remove it with `wsl --unregister CachyOS`.

## Reproducibility

The image is packed deterministically: the same packages always produce the same
`.wsl`. Builds on different days differ, because the CachyOS repositories are
rolling. See [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md).

## Credits

Built on the structure of the [Arch Linux WSL image](https://gitlab.archlinux.org/archlinux/archlinux-wsl).
The CPU detection and repository switch in `optimize-repos` come from the
[official CachyOS WSL image](https://github.com/CachyOS/cachyos-wsl).

## License

[GPL-3.0](LICENSE)
