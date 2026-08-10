# Vendored CachyOS mirrorlists

Pinned so the build is self-contained and host-independent. `build-image.sh`
repoints the injected `[cachyos*] Include = /etc/pacman.d/cachyos-*-mirrorlist`
paths at this directory.

Provenance:
- `cachyos-mirrorlist` — copied verbatim from the CachyOS `cachyos-mirrorlist`
  package (host `/etc/pacman.d/cachyos-mirrorlist`). Uses `$arch`.
- `cachyos-v3-mirrorlist` — the same mirror set with the `$arch_v3` hwcaps
  variable, which CachyOS's patched pacman expands to the x86-64-v3 repo path.

These are host copies rather than pins to a specific upstream
`cachyos*-mirrorlist` package release; `vendor/SHA256SUMS` fixes their content.
