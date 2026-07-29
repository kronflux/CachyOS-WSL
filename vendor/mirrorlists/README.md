# Vendored CachyOS mirrorlists

Pinned so the build is self-contained and host-independent (a build host set up
for one tier does not carry the other tiers' mirrorlist files). `build-image.sh`
repoints the injected `[cachyos*] Include = /etc/pacman.d/cachyos-*-mirrorlist`
paths at this directory.

Provenance:
- `cachyos-mirrorlist` — copied verbatim from the CachyOS `cachyos-mirrorlist`
  package (host `/etc/pacman.d/cachyos-mirrorlist`). Uses `$arch`.
- `cachyos-v4-mirrorlist` — copied verbatim from host `/etc/pacman.d/cachyos-v4-mirrorlist`.
  Uses `$arch_v4`.
- `cachyos-v3-mirrorlist` — generated from `cachyos-v4-mirrorlist` by substituting
  `$arch_v4` → `$arch_v3` (identical mirror set; only the hwcaps arch variable
  differs). CachyOS's patched pacman expands `$arch_v3`/`$arch_v4`.

TODO(P3): pin to specific upstream `cachyos*-mirrorlist` package versions with
checksums, and refresh via CI rather than host copy.
