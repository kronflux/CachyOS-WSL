#Requires -Version 5.1

<#
.SYNOPSIS
    Register a locally-built CachyOS .wsl image with WSL for pre-release testing.

.DESCRIPTION
    LOCAL TESTING ONLY. Before a public GitHub Release exists, this script lets
    you install a freshly-built .wsl image through the normal
    `wsl --install <name>` flow. It does so by pointing WSL's distribution-list
    URL at a local manifest that describes your image.

    What it does, step by step:
      1. Requires an elevated (Administrator) PowerShell session.
      2. Resolves the .wsl path and computes its SHA256 hash.
      3. Writes a one-distribution manifest to %TEMP%\cachywsl-manifest.json.
      4. Points the machine-wide WSL registry value 'DistributionListUrl' at that
         local manifest file. This is a single, reversible registry write.

    It performs NO network calls, handles NO credentials, and embeds NO secrets.

.PARAMETER WslPath
    Path to the locally-built .wsl image to register (e.g.
    output\cachyos-v3-<version>.wsl). Required.

.EXAMPLE
    # From an ELEVATED PowerShell prompt, at the repo root:
    .\windows\override-manifest.ps1 -WslPath output\cachyos-v3-2026.07.30.0.wsl
    wsl --install CachyOS-local

.NOTES
    Undo (removes the override; WSL reverts to the default online list):
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' -Name 'DistributionListUrl'
#>

param(
    [Parameter(Mandatory)]
    [string]$WslPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Registry location that WSL reads its distribution list URL from ----------
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss'
$regName = 'DistributionListUrl'

# --- Require Administrator elevation -------------------------------------------
# Writing under HKLM requires admin; failing up front gives a clearer message
# than a cryptic access-denied from Set-ItemProperty.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run from an ELEVATED PowerShell session (Run as Administrator). Right-click PowerShell -> 'Run as administrator', then re-run this command."
    exit 1
}

# --- Validate and resolve the .wsl path to an absolute path -------------------
if (-not (Test-Path -LiteralPath $WslPath -PathType Leaf)) {
    Write-Error "File not found: $WslPath"
    exit 1
}
$absWslPath = (Resolve-Path -LiteralPath $WslPath).Path
Write-Host "Image:  $absWslPath" -ForegroundColor Gray

# --- Compute the SHA256 hash of the image -------------------------------------
Write-Host "Computing SHA256 hash..." -ForegroundColor Yellow
$hash = (Get-FileHash -Algorithm SHA256 $absWslPath).Hash
Write-Host "SHA256: $hash" -ForegroundColor Gray

# --- Build the local manifest -------------------------------------------------
# file:// URLs use forward slashes; the third slash is the empty authority, so a
# Windows path 'C:\dir\img.wsl' becomes 'file:///C:/dir/img.wsl'.
$wslPathForwardSlashes = $absWslPath -replace '\\', '/'
$imageUrl = "file:///$wslPathForwardSlashes"

$manifest = [ordered]@{
    ModernDistributions = [ordered]@{
        CachyOS = @(
            [ordered]@{
                Name         = 'CachyOS-local'
                FriendlyName = 'CachyOS (local test)'
                Default      = $true
                Amd64Url     = [ordered]@{
                    Url    = $imageUrl
                    Sha256 = $hash
                }
            }
        )
    }
}

$manifestPath = "$env:TEMP\cachywsl-manifest.json"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "Manifest written: $manifestPath" -ForegroundColor Gray

# --- Set a single named registry value ----------------------------------------
# Nothing else under the key is touched; the exact undo command is printed below.
$manifestPathForwardSlashes = $manifestPath -replace '\\', '/'
$manifestUrl = "file:///$manifestPathForwardSlashes"
Set-ItemProperty -Path $regPath -Name $regName -Value $manifestUrl -Type String
Write-Host "Registry override set: $regPath\$regName = $manifestUrl" -ForegroundColor Gray

# --- Next steps + the EXACT undo ----------------------------------------------
Write-Host ""
Write-Host "Done. CachyOS-local is now registered for local testing." -ForegroundColor Green
Write-Host ""
Write-Host "Install it with:" -ForegroundColor Cyan
Write-Host "    wsl --install CachyOS-local"
Write-Host ""
Write-Host "When finished, UNDO the override with (removes the registry value):" -ForegroundColor Cyan
Write-Host "    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' -Name 'DistributionListUrl'"
Write-Host ""
