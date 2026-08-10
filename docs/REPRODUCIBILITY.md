# Reproducibility

CachyWSL targets **deterministic packaging + signed integrity**, not bit-identical
rebuilds across time (CachyOS ships rolling, frequently-rebuilt binary repos).

## What is guaranteed

- Deterministic pack: `TZ=UTC`, `SOURCE_DATE_EPOCH` from the image version, sorted
  tar (`--sort=name`), clamped mtimes, stripped atime/ctime, `--numeric-owner`,
  single-threaded `xz -9 -T1` (thread count does not affect output).
- Self-contained inputs: the build reads the CachyOS mirrorlist from
  `scripts/pacman.d/` and the Arch Linux mirrorlist from the rootfs overlay, not
  from the build host.
- Signed release: each `.wsl` ships a `.sha256` and a Cosign keyless signature
  bundle, verified in CI right after signing. Verify:

  ```bash
  cosign verify-blob cachyos-<ver>.wsl --bundle cachyos-<ver>.wsl.bundle \
    --certificate-identity-regexp '^https://github\.com/kronflux/CachyOS-WSL/\.github/workflows/release\.yml@refs/(heads/main|tags/20[0-9.]+)$' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

## What is NOT guaranteed

- Two builds days apart pull different upstream package versions from the rolling
  CachyOS/Arch repos, so the resulting `.wsl` bytes differ. CachyOS has no dated
  archive of its repositories (Arch Linux's bit-for-bit reproducible WSL image
  builds against the Arch Linux Archive), so package versions cannot be pinned
  to a date.
