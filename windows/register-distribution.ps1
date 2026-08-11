#Requires -Version 5.1
<#
.SYNOPSIS
    Register CachyOS with WSL and install it.

.DESCRIPTION
    Adds CachyOS to the WSL distribution list via the DistributionListUrlAppend
    registry value (append, not override — the stock online list is preserved),
    ensures WSL 2 is installed and the default version, then runs
    `wsl --install CachyOS`.

    The script self-elevates: writing under HKLM and installing WSL both require
    Administrator. Every step reports its own result and the run ends with a
    summary. Nothing is written outside the Lxss registry key and (for -Local)
    a manifest under %ProgramData%\CachyWSL.

.PARAMETER Local
    Path to a locally-built .wsl to register for pre-release testing, instead of
    the published distribution list.

.PARAMETER Remove
    Undo the registry change and revert WSL to the stock online list.

.PARAMETER NoInstall
    Set up the distribution list but do not run `wsl --install`.

.EXAMPLE
    # From any PowerShell (it elevates itself):
    .\windows\register-distribution.ps1

.EXAMPLE
    # One-paste (uses defaults; advanced flags need the downloaded script):
    irm https://github.com/kronflux/CachyOS-WSL/releases/latest/download/register-distribution.ps1 | iex

.EXAMPLE
    # Register and install a locally-built image before a release exists:
    .\windows\register-distribution.ps1 -Local output\cachyos-v3-2026.08.11.1.wsl
#>
[CmdletBinding()]
param(
    [string]$Local,
    [switch]$Remove,
    [switch]$NoInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SlugUrl      = 'https://github.com/kronflux/CachyOS-WSL/releases/latest/download'
$DistUrl      = "$SlugUrl/DistributionInfo.json"
$SelfUrl      = "$SlugUrl/register-distribution.ps1"
$RegPath      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss'
$AppendName   = 'DistributionListUrlAppend'
$LocalDir     = Join-Path $env:ProgramData 'CachyWSL'
$LocalInfo    = Join-Path $LocalDir 'DistributionInfo.json'
$DistroName   = 'CachyOS'

# --- self-elevate -------------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $hostExe = (Get-Process -Id $PID).Path
    $psArgs  = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($PSCommandPath) {
        $psArgs += @('-File', $PSCommandPath)
        if ($Local)     { $psArgs += @('-Local', $Local) }
        if ($Remove)    { $psArgs += '-Remove' }
        if ($NoInstall) { $psArgs += '-NoInstall' }
    } else {
        # Running in-memory (irm | iex): re-fetch inside the elevated session.
        $psArgs += @('-Command', "irm $SelfUrl | iex")
    }
    try { Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $psArgs }
    catch { Write-Host "Elevation was declined. Re-run from an Administrator PowerShell." -ForegroundColor Yellow }
    return
}

# --- palette (same family as the Linux OOBE; degrades without a VT console) ----
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new() } catch {}
$E = [char]27
if ($Host.UI.SupportsVirtualTerminal -or $env:WT_SESSION) {
    $R = "$E[0m"; $TEAL = "$E[38;5;44m"; $BTEAL = "$E[1;38;5;44m"
    $GN = "$E[38;5;42m"; $DIM = "$E[38;5;242m"; $RED = "$E[38;5;203m"
} else { $R = ''; $TEAL = ''; $BTEAL = ''; $GN = ''; $DIM = ''; $RED = '' }
$CHK  = [char]0x2713; $RING = [char]0x25CB; $CROSS = [char]0x2717
$ELB  = [char]0x2514; $BH = [char]0x2500; $BV = [char]0x2502
$BTL  = [char]0x256D; $BTR = [char]0x256E; $BBL = [char]0x2570; $BBR = [char]0x256F
$RULE = [string]($BH) * 60
$Total = if ($Remove) { 2 } else { 4 }
$Step = 0

function Write-Rule { Write-Host "$TEAL$RULE$R" }
function Write-Banner([string]$title, [string]$sub) {
    Write-Host ''; Write-Rule
    Write-Host " $BTEAL$title$R"
    Write-Rule
    if ($sub) { Write-Host " $DIM$ELB $sub$R" }
    Write-Host ''
}
function Write-Step([string]$label, [string]$value, [string]$state) {
    $script:Step++
    $glyph = switch ($state) {
        'ok'   { "$GN$CHK$R" }
        'fail' { "$RED$CROSS$R" }
        default { "$DIM$RING$R" }
    }
    $lead = '[{0}/{1}] {2}' -f $script:Step, $script:Total, $label
    $dots = $DIM + ([string]('.' * [Math]::Max(3, 34 - $lead.Length))) + $R
    Write-Host ('  {0} {1} {2} {3}' -f $lead, $dots, ("$value").PadRight(16), $glyph)
}
function Write-Note([string]$m) { Write-Host "  $DIM$m$R" }
function Write-SummaryBox([object[]]$rows) {
    $w = 46
    Write-Host ''
    Write-Host ("$TEAL$BTL$BH CachyOS on WSL " + ([string]($BH) * ($w - 16)) + "$BTR$R")
    foreach ($row in $rows) {
        $label = [string]$row[0]; $ok = [bool]$row[1]
        $glyph = if ($ok) { "$GN$CHK$R" } else { "$DIM$RING$R" }
        $dots = [string]('.' * ($w - $label.Length - 4))
        Write-Host ("$TEAL$BV$R $label $DIM$dots$R $glyph $TEAL$BV$R")
    }
    Write-Host ("$TEAL$BBL" + ([string]($BH) * $w) + "$BBR$R")
}
function Pause-Exit([int]$code) {
    Write-Host ''
    if ([Environment]::UserInteractive) { [void](Read-Host 'Press Enter to close') }
    exit $code
}

# --- remove mode --------------------------------------------------------------
if ($Remove) {
    Write-Banner 'CachyOS on WSL' 'Remove distribution list entry'
    $had = $false
    if (Get-ItemProperty -Path $RegPath -Name $AppendName -ErrorAction SilentlyContinue) { $had = $true }
    Remove-ItemProperty -Path $RegPath -Name $AppendName -ErrorAction SilentlyContinue
    Write-Step 'Registry entry' $(if ($had) { 'removed' } else { 'not set' }) 'ok'
    if (Test-Path $LocalInfo) { Remove-Item $LocalInfo -Force -ErrorAction SilentlyContinue }
    Write-Step 'Local manifest' 'cleaned' 'ok'
    Write-SummaryBox @(, @('Distribution list reverted', $true))
    Write-Host ''
    Write-Host " $GN`Done.$R WSL is back to the stock online list."
    Pause-Exit 0
}

Write-Banner 'CachyOS on WSL' 'Windows setup'

# --- 1. elevation (guaranteed by the self-elevate above) ----------------------
Write-Step 'Administrator' 'elevated' 'ok'

# --- 2. ensure WSL 2 ----------------------------------------------------------
$wslOk = $false; $rebootNeeded = $false; $wslState = 'ready'
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($wsl) { & wsl.exe --status 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $wslOk = $true } }
if (-not $wslOk) {
    Write-Note 'WSL not detected — installing (this may require a reboot)...'
    & wsl.exe --install --no-distribution 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $rebootNeeded = $true; $wslState = 'installed' }
    else { $wslState = 'install failed' }
}
# make WSL 2 the default so CachyOS installs as v2 (switches v1 defaults over)
& wsl.exe --set-default-version 2 2>&1 | Out-Null
Write-Step 'WSL 2 runtime' $wslState $(if ($wslState -eq 'install failed') { 'fail' } else { 'ok' })

if ($rebootNeeded) {
    Write-Note 'WSL was just installed. Reboot Windows, then run this script again to finish.'
}

# --- 3. register the distribution list ----------------------------------------
$regValue = $DistUrl
if ($Local) {
    if (-not (Test-Path -LiteralPath $Local -PathType Leaf)) {
        Write-Step 'Register CachyOS' 'file not found' 'fail'
        Write-Note "No such .wsl: $Local"
        Pause-Exit 1
    }
    $wslFull = (Resolve-Path -LiteralPath $Local).Path
    $sha = (Get-FileHash -LiteralPath $wslFull -Algorithm SHA256).Hash.ToLower()
    New-Item -ItemType Directory -Force -Path $LocalDir | Out-Null
    $info = [ordered]@{ ModernDistributions = [ordered]@{ CachyOS = @(
        [ordered]@{
            Name         = $DistroName
            FriendlyName = 'CachyOS (local build)'
            Default      = $true
            Amd64Url     = [ordered]@{ Url = $wslFull; Sha256 = $sha }
        }) } }
    $info | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $LocalInfo -Encoding UTF8
    $regValue = $LocalInfo
}
New-ItemProperty -Path $RegPath -Name $AppendName -Value $regValue -PropertyType String -Force | Out-Null
Write-Step 'Register CachyOS' $(if ($Local) { 'local build' } else { 'list appended' }) 'ok'

# --- 4. install ---------------------------------------------------------------
$installed = $false
if ($rebootNeeded) {
    Write-Step 'Install CachyOS' 'after reboot' 'skip'
} elseif ($NoInstall) {
    Write-Step 'Install CachyOS' 'skipped' 'skip'
    Write-Note "Run it yourself with:  wsl --install $DistroName"
} else {
    Write-Host ''
    Write-Host " $DIM`Running: wsl --install $DistroName$R"
    Write-Host ''
    & wsl.exe --install $DistroName
    $installed = ($LASTEXITCODE -eq 0)
    Write-Step 'Install CachyOS' $(if ($installed) { 'installed' } else { 'see output' }) $(if ($installed) { 'ok' } else { 'fail' })
}

# --- summary ------------------------------------------------------------------
Write-SummaryBox @(
    @('Administrator', $true),
    @('WSL 2 runtime', ($wslState -ne 'install failed')),
    @('CachyOS registered', $true),
    @('CachyOS installed', $installed)
)
Write-Host ''
if ($installed) {
    Write-Host " $GN`Ready.$R Launch it any time with:  wsl -d $DistroName"
} elseif ($rebootNeeded) {
    Write-Host " $BTEAL`Reboot required.$R After rebooting, re-run this script to install CachyOS."
} else {
    Write-Host " $BTEAL`Next:$R  wsl --install $DistroName"
}
Pause-Exit 0
