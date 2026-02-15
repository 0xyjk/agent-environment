# agent-environment uninstaller (PowerShell)
# Removes tools installed by install.ps1 without touching other files in AGENTS_HOME.
#
# Usage:
#   pwsh uninstall.ps1

$ErrorActionPreference = "Stop"

# ─── Configuration ────────────────────────────────────────────

$AgentsHome = if ($env:AGENTS_HOME) { $env:AGENTS_HOME } else { Join-Path $HOME ".agents" }

# ─── Output Helpers ───────────────────────────────────────────

function Write-Info  { param([string]$Message) Write-Host "[info]  $Message" -ForegroundColor Blue }
function Write-Ok    { param([string]$Message) Write-Host "[ok]    $Message" -ForegroundColor Green }

# ─── Remove Installed Files ──────────────────────────────────

function Remove-InstalledFiles {
    Write-Info "Removing installed files from $AgentsHome..."

    $dirs = @("bin", "python", "venv", "fnm")
    foreach ($dir in $dirs) {
        $path = Join-Path $AgentsHome $dir
        if (Test-Path $path) {
            Remove-Item $path -Recurse -Force
            Write-Ok "Removed $path"
        }
    }

    $files = @("env.sh", "env.ps1")
    foreach ($file in $files) {
        $path = Join-Path $AgentsHome $file
        if (Test-Path $path) {
            Remove-Item $path -Force
            Write-Ok "Removed $path"
        }
    }

    # Remove AGENTS_HOME if empty
    if (Test-Path $AgentsHome) {
        $remaining = Get-ChildItem $AgentsHome -Force
        if (-not $remaining) {
            Remove-Item $AgentsHome -Force
            Write-Ok "Removed empty directory $AgentsHome"
        } else {
            Write-Info "$AgentsHome still contains other files, keeping it."
        }
    }
}

# ─── Clean PowerShell Profile ────────────────────────────────

function Clean-ShellProfile {
    $profilePath = $PROFILE.CurrentUserAllHosts
    $marker = "# agent-environment"

    if (-not (Test-Path $profilePath)) { return }

    $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content -or -not $content.Contains($marker)) { return }

    # Remove marker line and the line after it
    $lines = Get-Content $profilePath
    $newLines = @()
    $skipNext = $false

    foreach ($line in $lines) {
        if ($skipNext) {
            $skipNext = $false
            continue
        }
        if ($line.Contains($marker)) {
            $skipNext = $true
            continue
        }
        $newLines += $line
    }

    # Trim trailing empty lines
    while ($newLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($newLines[-1])) {
        $newLines = $newLines[0..($newLines.Count - 2)]
    }

    Set-Content -Path $profilePath -Value ($newLines -join "`n") -Encoding UTF8
    Write-Ok "Cleaned $profilePath"
}

# ─── Main ────────────────────────────────────────────────────

function Main {
    Write-Host ""
    Write-Info "agent-environment uninstaller"
    Write-Info "AGENTS_HOME: $AgentsHome"
    Write-Host ""

    Remove-InstalledFiles
    Write-Host ""

    Write-Info "Cleaning shell profile..."
    Clean-ShellProfile
    Write-Host ""

    Write-Ok "Uninstall complete. Restart your terminal to apply changes."
    Write-Host ""
}

Main
