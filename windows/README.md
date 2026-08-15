# Windows-side helpers

PowerShell helpers for installing CachyOS on Windows and styling the terminal.
They run on Windows PowerShell 5.1+ / PowerShell 7+.

## Scripts

### `register-distribution.ps1` — register CachyOS with WSL and install it

Adds CachyOS to the WSL distribution list via the `DistributionListUrlAppend`
registry value (**append**, so Microsoft's online list is preserved), ensures
WSL 2 is installed and the default version, then runs `wsl --install CachyOS`.

- **Self-elevating** — it relaunches itself under UAC (writing `HKLM` and
  installing WSL need Administrator). Works both as a saved file and via
  `irm … | iex`.
- **WSL 2** — provisions the prerequisites in place: firmware virtualization and
  `hypervisorlaunchtype`, the `Microsoft-Windows-Subsystem-Linux` and
  `VirtualMachinePlatform` features, supporting services, the WSL runtime, and
  the default version. It prints a line only when it changes something or hits a
  blocker (e.g. virtualization disabled in BIOS), and flags a required restart.
- Reports each step and closes with a summary. `-Local` installs the file
  directly with `wsl --install --from-file` (no manifest, no download).

Published release (default):

```powershell
# Elevates itself; installs the latest signed release as `CachyOS`.
.\windows\register-distribution.ps1

# One-paste equivalent (uses defaults; advanced flags need the downloaded script):
irm https://github.com/kronflux/CachyOS-WSL/releases/latest/download/register-distribution.ps1 | iex
```

Local build (pre-release testing):

```powershell
.\windows\register-distribution.ps1 -Local output\cachyos-v3-<version>.wsl
```

Options: `-Local <path>` install a locally-built `.wsl` directly (via
`--from-file`) instead of the published list · `-NoInstall` set up the list but
skip the install · `-Remove` undo the registry change and revert to the stock
online list.

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

**Undo** — restore the backup it created (the exact path is printed when it runs):

```powershell
Copy-Item "<settings.json path>.bak" "<settings.json path>" -Force
```

## End-to-end (local build)

1. **Build a `.wsl`** on your CachyOS/Arch (WSL) build host — see the repo
   [`README.md`](../README.md):
   ```bash
   make build     # -> output/cachyos-v3-<version>.wsl
   ```
2. **Register and install it** (the script elevates itself):
   ```powershell
   .\windows\register-distribution.ps1 -Local output\cachyos-v3-<version>.wsl
   ```
3. *(optional)* **Style Windows Terminal**:
   ```powershell
   .\windows\setup-terminal.ps1
   ```
4. **Test**, then **undo**:
   ```powershell
   wsl --unregister CachyOS
   .\windows\register-distribution.ps1 -Remove
   # and, if you ran setup-terminal.ps1, restore settings.json from its .bak
   ```
