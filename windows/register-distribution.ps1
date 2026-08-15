#Requires -Version 5.1
<#
.SYNOPSIS
    Register CachyOS with WSL and install it.

.DESCRIPTION
    Adds CachyOS to the WSL distribution list via the DistributionListUrlAppend
    registry value (append, not override -- the stock online list is preserved),
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
    [switch]$NoInstall,
    [switch]$Elevated   # internal: set on the UAC relaunch
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
$HostExe  = (Get-Process -Id $PID).Path
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $psArgs  = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($PSCommandPath) {
        $psArgs += @('-File', $PSCommandPath, '-Elevated')
        if ($Local)     { $psArgs += @('-Local', $Local) }
        if ($Remove)    { $psArgs += '-Remove' }
        if ($NoInstall) { $psArgs += '-NoInstall' }
    } else {
        # Running in-memory (irm | iex): re-fetch inside the elevated session.
        $psArgs += @('-Command', "`$env:CACHYWSL_ELEVATED='1'; irm $SelfUrl | iex")
    }
    try { Start-Process -FilePath $HostExe -Verb RunAs -ArgumentList $psArgs }
    catch { Write-Host "Elevation was declined. Re-run from an Administrator PowerShell." -ForegroundColor Yellow }
    return
}
# True when this is the (transient) window our own UAC relaunch opened.
$IsRelaunched = [bool]$Elevated -or ($env:CACHYWSL_ELEVATED -eq '1')

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
    # Only the window our own UAC relaunch opened needs to be held open to be
    # read; a session the user already had stays put on its own.
    if ($script:IsRelaunched -and [Environment]::UserInteractive) {
        Write-Host ''
        [void](Read-Host 'Press Enter to close')
    }
    exit $code
}

function Initialize-Wsl2 {
    # Provision the WSL 2 prerequisites in place. Emits a dim note only when it
    # changes something or hits a blocker; otherwise silent. Returns one of
    # 'ready' | 'reboot' | 'blocked'.
    $reboot = $false
    $sys = Join-Path $env:SystemRoot 'System32'

    $os = Get-CimInstance Win32_OperatingSystem
    if ([int]$os.BuildNumber -lt 19041) {
        Write-Note "Windows build $($os.BuildNumber) is below 19041; update Windows first."; return 'blocked'
    }
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($arch -ne 'AMD64' -and $arch -ne 'ARM64') {
        Write-Note "Unsupported CPU architecture ($arch); WSL 2 needs x64 or arm64."; return 'blocked'
    }

    # virtualization / hypervisor launch policy
    if (-not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent) {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        if (-not $cpu.VirtualizationFirmwareEnabled -and -not $cpu.SecondLevelAddressTranslationExtensions) {
            Write-Note 'Enable virtualization (Intel VT-x / AMD-V) in your BIOS/UEFI, then re-run.'; return 'blocked'
        }
        $bcd = Join-Path $sys 'bcdedit.exe'
        if (((& $bcd /enum '{current}' 2>$null) -join "`n") -match '(?im)^\s*hypervisorlaunchtype\s+Off\s*$') {
            & $bcd /set '{current}' hypervisorlaunchtype Auto | Out-Null
            Write-Note 'Enabled the hypervisor launch type (restart required).'; $reboot = $true
        }
    }

    # optional features
    foreach ($feat in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $feat -ErrorAction SilentlyContinue
        if (-not $f) { Write-Note "Could not query the $feat feature."; return 'blocked' }
        if ($f.State -ne 'Enabled') {
            if ($f.State -eq 'DisabledWithPayloadRemoved') {
                Write-Note "$feat is unavailable on this image (payload removed)."; return 'blocked'
            }
            Enable-WindowsOptionalFeature -Online -FeatureName $feat -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Note "Enabled $feat (restart required)."; $reboot = $true
        }
    }

    # supporting services must not be Disabled
    foreach ($svc in @('HvHost', 'vmcompute', 'LxssManager', 'WslService')) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.StartType -eq 'Disabled') {
            Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
            Write-Note "Re-enabled the $svc service."
        }
    }

    if ($reboot) { return 'reboot' }

    # WSL runtime package
    & wsl.exe --status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Note 'Installing the WSL runtime...'
        & wsl.exe --install --no-distribution 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Note 'wsl --install failed; run "wsl --install" manually, then re-run.'; return 'blocked' }
        return 'reboot'
    }

    & wsl.exe --set-default-version 2 2>&1 | Out-Null   # switches a v1 default over
    return 'ready'
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

# --- 2. WSL 2 prerequisites (virtualization, features, services, runtime) -----
$wslState     = Initialize-Wsl2
$rebootNeeded = ($wslState -eq 'reboot')
$wslFailed    = ($wslState -eq 'blocked')
Write-Step 'WSL 2 runtime' `
    $(switch ($wslState) { 'ready' { 'ready' } 'reboot' { 'reboot needed' } default { 'blocked' } }) `
    $(switch ($wslState) { 'ready' { 'ok' }    'reboot' { 'skip' }          default { 'fail' } })
if ($wslFailed) {
    Write-SummaryBox @(
        @('Administrator', $true),
        @('WSL 2 runtime', $false),
        @('CachyOS registered', $false),
        @('CachyOS installed', $false))
    Write-Host ''
    Write-Host " $RED`Blocked.$R WSL 2 prerequisites are not satisfied -- see the log above."
    Pause-Exit 1
}

# --- 3. register (published) or resolve the local image -----------------------
# The distribution list points at a *downloadable* URL, so a local build is
# installed directly with --from-file instead of through the list.
if ($Local) {
    if (-not (Test-Path -LiteralPath $Local -PathType Leaf)) {
        Write-Step 'Local image' 'not found' 'fail'
        Write-Note "No such .wsl: $Local"
        Pause-Exit 1
    }
    $wslFull = (Resolve-Path -LiteralPath $Local).Path
    # drop any stale append so the list can't point at a now-missing image
    Remove-ItemProperty -Path $RegPath -Name $AppendName -ErrorAction SilentlyContinue
    if (Test-Path $LocalInfo) { Remove-Item $LocalInfo -Force -ErrorAction SilentlyContinue }
    Write-Step 'Local image' (Split-Path $wslFull -Leaf) 'ok'
} else {
    New-ItemProperty -Path $RegPath -Name $AppendName -Value $DistUrl -PropertyType String -Force | Out-Null
    Write-Step 'Register CachyOS' 'list appended' 'ok'
}

# --- 4. install (without launching; first-run setup is handed off below) ------
$installed = $false
if ($rebootNeeded) {
    Write-Step 'Install CachyOS' 'after reboot' 'skip'
} elseif ($NoInstall) {
    Write-Step 'Install CachyOS' 'skipped' 'skip'
} else {
    Write-Host ''
    if ($Local) { & wsl.exe --install --from-file "$wslFull" --no-launch }
    else        { & wsl.exe --install $DistroName --no-launch }
    $installed = ($LASTEXITCODE -eq 0)
    Write-Host ''
    Write-Step 'Install CachyOS' $(if ($installed) { 'installed' } else { 'see output' }) $(if ($installed) { 'ok' } else { 'fail' })
}

# --- finish -------------------------------------------------------------------
# On a fresh install, hand straight off to first-run setup so the step report
# above is the last thing shown before the OOBE takes over: no trailing summary
# box, and no key press to "complete" the script.
if ($installed -and -not $rebootNeeded) {
    Write-Host ''
    Write-Host " $GN`Installed.$R Starting first-run setup..."
    Write-Host ''
    & wsl.exe -d $DistroName
    exit 0
}

Write-SummaryBox @(
    @('Administrator', $true),
    @('WSL 2 runtime', (-not $wslFailed)),
    @($(if ($Local) { 'Local image ready' } else { 'CachyOS registered' }), $true),
    @('CachyOS installed', $installed)
)
Write-Host ''
if ($rebootNeeded) {
    Write-Host " $BTEAL`Reboot required.$R After restarting, re-run this to finish."
} elseif ($NoInstall) {
    if ($Local) { Write-Host " $BTEAL`Next:$R  wsl --install --from-file `"$wslFull`" --no-launch; wsl -d $DistroName" }
    else        { Write-Host " $BTEAL`Next:$R  wsl --install $DistroName" }
} else {
    Write-Host " $BTEAL`Next:$R  wsl -d $DistroName"
}
Pause-Exit 0
