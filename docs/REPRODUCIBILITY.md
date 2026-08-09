# Reproducibility

CachyWSL targets **deterministic packaging + signed integrity**, not bit-identical
rebuilds across time (CachyOS ships rolling, frequently-rebuilt binary repos).

## What is guaranteed
- Deterministic pack: `TZ=UTC`, `SOURCE_DATE_EPOCH` from the image version, sorted
  tar (`--sort=name`), clamped mtimes, stripped atime/ctime, `--numeric-owner`,
  single-threaded `xz -9 -T1` (thread count does not affect output).
- Pinned text assets: the CachyOS repo AWK transforms, mirrorlists, and makepkg
  presets under `vendor/` are checksum-pinned (`vendor/SHA256SUMS`, enforced by
  `scripts/verify-vendor.sh` and in CI).
- Signed release: each `.wsl` ships a `.sha256` and a Cosign keyless signature
  bundle. Verify:
  `cosign verify-blob cachyos-v3-<ver>.wsl --bundle cachyos-v3-<ver>.wsl.bundle \
    --certificate-identity-regexp 'https://github.com/kronflux/CachyOS-WSL/.*' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com`

## What is NOT guaranteed
- Two builds days apart pull different upstream package versions from the rolling
  CachyOS/Arch repos, so the resulting `.wsl` bytes differ. Binary-package
  snapshotting is intentionally not done (fights the rolling model, bloats the repo).
