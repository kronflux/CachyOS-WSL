# Windows-side testing tooling

PowerShell helpers for **local, pre-release testing** of a CachyOS `.wsl` image
on Windows — for use **before** a public GitHub Release exists (once a release
is published, you install the normal way and don't need these).

> Runtime note: these scripts run on Windows PowerShell 5.1+ / PowerShell 7+.
> They make **no network calls**, handle **no credentials**, and contain **no
> secrets**.

## Scripts

### `override-manifest.ps1` — register a local `.wsl` with WSL

Points WSL's distribution-list URL at a local manifest describing your freshly
built image, so you can install it through the normal `wsl --install <name>`
flow as `CachyOS-local`.

- **Must be run in an ELEVATED PowerShell** ("Run as administrator"). It writes
  a single value under `HKLM`, so it checks for Administrator up front and exits
  with guidance if not elevated.
- The registry write is a single named value and is fully reversible.

```powershell
# Elevated PowerShell, at the repo root:
.\windows\override-manifest.ps1 -WslPath output\cachyos-v3-<version>.wsl
wsl --install CachyOS-local
```

**Undo** (removes the override; WSL reverts to the default online list):

```powershell
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' -Name 'DistributionListUrl'
```

### `setup-terminal.ps1` — apply the CachyOS Windows Terminal look

Merges the repo's `rootfs/usr/lib/wsl/terminal-profile.json` into your Windows
Terminal `settings.json`: adds the **CachyOS** color scheme (if missing) and
applies the CachyOS font / opacity / acrylic / colorScheme to any profile whose
name starts with `CachyOS`.

- **Backs up** `settings.json` to `settings.json.bak` before writing.
- **Idempotent** — re-running adds nothing new.
- Does not require elevation. If Windows Terminal isn't installed, it warns and
  exits cleanly.

```powershell
.\windows\setup-terminal.ps1
```

**Undo** — restore the backup it created (the exact path is printed when it
runs):

```powershell
Copy-Item "<settings.json path>.bak" "<settings.json path>" -Force
```

## End-to-end flow

1. **Build a `.wsl`** on your CachyOS/Arch (WSL) build host — see the repo
   [`README.md`](../README.md):
   ```bash
   make build     # -> output/cachyos-v3-<version>.wsl
   ```
2. **Register it** for testing (elevated PowerShell, repo root):
   ```powershell
   .\windows\override-manifest.ps1 -WslPath output\cachyos-v3-<version>.wsl
   ```
3. **Install** it:
   ```powershell
   wsl --install CachyOS-local
   ```
4. *(optional)* **Style Windows Terminal**:
   ```powershell
   .\windows\setup-terminal.ps1
   ```
5. **Test**, then **undo**:
   ```powershell
   wsl --unregister CachyOS-local
   Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' -Name 'DistributionListUrl'
   # and, if you ran setup-terminal.ps1, restore settings.json from its .bak
   ```
