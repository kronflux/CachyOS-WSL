#Requires -Version 5.1

<#
.SYNOPSIS
    Merge the CachyOS color scheme (and profile styling) into Windows Terminal.

.DESCRIPTION
    LOCAL / POST-INSTALL helper. Windows Terminal auto-generates a profile for a
    newly installed WSL distribution, but it does not pull in the CachyOS color
    scheme. This script:
      1. Locates the Windows Terminal settings.json.
      2. Backs it up to settings.json.bak (overwriting any previous backup).
      3. Reads the image's terminal-profile.json from this repo.
      4. Adds the "CachyOS" color scheme if it is not already present.
      5. Applies the CachyOS font / opacity / acrylic / colorScheme to any
         existing profile whose name starts with "CachyOS".

    It is idempotent: re-running it adds nothing new and makes no further changes
    once the scheme is present and the profile is styled. It performs NO network
    calls, handles NO credentials, and embeds NO secrets.

.EXAMPLE
    .\windows\setup-terminal.ps1

.NOTES
    Undo: restore the backup that this script created, e.g.
        Copy-Item "<settings.json>.bak" "<settings.json>" -Force
    The backup path is printed when the script runs.
#>

param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Locate Windows Terminal settings.json ------------------------------------
$settings = Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json" -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $settings) {
    Write-Warning "Windows Terminal settings.json not found. Is Windows Terminal installed and has it been launched at least once? Nothing to do."
    exit 0
}
Write-Host "Settings: $($settings.FullName)" -ForegroundColor Gray

# --- Back up settings.json before writing -------------------------------------
$backupPath = "$($settings.FullName).bak"
Copy-Item -LiteralPath $settings.FullName -Destination $backupPath -Force
Write-Host "Backup:   $backupPath" -ForegroundColor Gray

# --- Read the repo's terminal profile template --------------------------------
$templatePath = Join-Path $PSScriptRoot '..\rootfs\usr\lib\wsl\terminal-profile.json'
if (-not (Test-Path -LiteralPath $templatePath)) {
    Write-Error "Terminal profile template not found: $templatePath"
    exit 1
}
# Windows Terminal's settings.json is JSONC (it ships with `//` and `/* */`
# comments). ConvertFrom-Json on PS 5.1 rejects comments, so strip them first
# with a scanner that ignores comment markers appearing inside strings.
function Remove-JsonComment {
    param([string]$Text)
    $out = New-Object System.Text.StringBuilder
    $inStr = $false; $esc = $false; $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inStr) {
            [void]$out.Append($c)
            if ($esc)              { $esc = $false }
            elseif ($c -eq '\')    { $esc = $true }
            elseif ($c -eq '"')    { $inStr = $false }
            $i++; continue
        }
        if ($c -eq '"') { $inStr = $true; [void]$out.Append($c); $i++; continue }
        if ($c -eq '/' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '/') {
            while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }   # line comment
            continue
        }
        if ($c -eq '/' -and ($i + 1) -lt $n -and $Text[$i + 1] -eq '*') {
            $i += 2                                              # block comment
            while (($i + 1) -lt $n -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }
            $i += 2; continue
        }
        [void]$out.Append($c); $i++
    }
    $out.ToString()
}

$template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
$json     = ConvertFrom-Json (Remove-JsonComment (Get-Content -LiteralPath $settings.FullName -Raw))

$changes = New-Object System.Collections.Generic.List[string]

# Helper: set a property, adding it if it does not already exist.
function Set-Prop {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

# --- Merge the CachyOS color scheme (idempotent by .name) ---------------------
$templateScheme = $template.schemes | Select-Object -First 1
$schemeName     = $templateScheme.name

if (-not ($json.PSObject.Properties.Name -contains 'schemes')) {
    Set-Prop -Object $json -Name 'schemes' -Value @()
}
$existingScheme = @($json.schemes) | Where-Object { $_.name -eq $schemeName }
if (-not $existingScheme) {
    $json.schemes = @($json.schemes) + $templateScheme
    $changes.Add("Added color scheme '$schemeName'.")
} else {
    $changes.Add("Color scheme '$schemeName' already present; left unchanged.")
}

# --- Style any existing CachyOS* profile (WSL auto-creates this profile) -------
# Windows Terminal stores user profiles under profiles.list; older/edge layouts
# store them as a bare profiles array. Support both.
$profileList = @()
if ($json.PSObject.Properties.Name -contains 'profiles') {
    if ($json.profiles -is [System.Array]) {
        $profileList = @($json.profiles)
    } elseif ($json.profiles.PSObject.Properties.Name -contains 'list') {
        $profileList = @($json.profiles.list)
    }
}

$templateProfile = $template.profiles | Select-Object -First 1
$matched = @($profileList | Where-Object { $_.name -like 'CachyOS*' })

if ($matched.Count -eq 0) {
    $changes.Add("No 'CachyOS*' profile found yet; install the distro first, then re-run. Scheme is still available to apply manually.")
} else {
    foreach ($p in $matched) {
        Set-Prop -Object $p -Name 'colorScheme' -Value $schemeName
        Set-Prop -Object $p -Name 'font'        -Value $templateProfile.font
        Set-Prop -Object $p -Name 'opacity'     -Value $templateProfile.opacity
        Set-Prop -Object $p -Name 'useAcrylic'  -Value $templateProfile.useAcrylic
        $changes.Add("Styled profile '$($p.name)' (colorScheme=$schemeName, font/opacity/useAcrylic applied).")
    }
}

# --- Write settings back ------------------------------------------------------
$json | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $settings.FullName -Encoding UTF8

# --- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "Windows Terminal updated. Summary of changes:" -ForegroundColor Green
foreach ($c in $changes) { Write-Host "  - $c" }
Write-Host ""
Write-Host "If anything looks wrong, restore the backup:" -ForegroundColor Cyan
Write-Host "    Copy-Item '$backupPath' '$($settings.FullName)' -Force"
Write-Host ""
