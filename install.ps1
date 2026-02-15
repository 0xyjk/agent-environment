# agent-environment installer (PowerShell)
# Installs uv, Python, fnm, and Node.js into a self-contained directory.
#
# Usage:
#   pwsh install.ps1
#   irm https://raw.githubusercontent.com/0xyjk/agent-environment/main/install.ps1 | iex
#
# Environment variables:
#   AGENTS_HOME            - Install root (default: ~/.agents)
#   AGENTS_UV_VERSION      - uv version to install (default: latest)
#   AGENTS_PYTHON_VERSION  - Python version (default: 3.12)
#   AGENTS_FNM_VERSION     - fnm version to install (default: latest)
#   AGENTS_NODE_VERSION    - Node.js major version (default: 20)

$ErrorActionPreference = "Stop"

# ─── Configuration ────────────────────────────────────────────

$AgentsHome = if ($env:AGENTS_HOME) { $env:AGENTS_HOME } else { Join-Path $HOME ".agents" }
$UvVersion = if ($env:AGENTS_UV_VERSION) { $env:AGENTS_UV_VERSION } else { "latest" }
$PythonVersion = if ($env:AGENTS_PYTHON_VERSION) { $env:AGENTS_PYTHON_VERSION } else { "3.12" }
$FnmVersion = if ($env:AGENTS_FNM_VERSION) { $env:AGENTS_FNM_VERSION } else { "latest" }
$NodeVersion = if ($env:AGENTS_NODE_VERSION) { $env:AGENTS_NODE_VERSION } else { "20" }

$MinUvVersion = [version]"0.6.0"
$MinNodeMajor = 20

$BinDir = Join-Path $AgentsHome "bin"
$PythonDir = Join-Path $AgentsHome "python"
$VenvDir = Join-Path $AgentsHome "venv"
$FnmDir = Join-Path $AgentsHome "fnm"

# Track resolved paths
$script:UvPath = $null
$script:FnmPath = $null

# ─── Output Helpers ───────────────────────────────────────────

function Write-Info  { param([string]$Message) Write-Host "[info]  $Message" -ForegroundColor Blue }
function Write-Ok    { param([string]$Message) Write-Host "[ok]    $Message" -ForegroundColor Green }
function Write-Warn  { param([string]$Message) Write-Host "[warn]  $Message" -ForegroundColor Yellow }
function Write-Err   { param([string]$Message) Write-Host "[error] $Message" -ForegroundColor Red }

function Stop-WithError {
    param([string]$Message)
    Write-Err $Message
    exit 1
}

# ─── Version Helpers ──────────────────────────────────────────

function Get-UvVersion {
    param([string]$UvBin)
    try {
        $output = & $UvBin --version 2>$null
        if ($output -match "^uv (\d+\.\d+\.\d+)") {
            return [version]$Matches[1]
        }
    } catch {}
    return $null
}

function Get-NodeMajor {
    param([string]$NodeBin)
    try {
        $output = & $NodeBin --version 2>$null
        if ($output -match "^v(\d+)\.") {
            return [int]$Matches[1]
        }
    } catch {}
    return $null
}

# ─── uv ──────────────────────────────────────────────────────

function Resolve-Uv {
    Write-Info "Resolving uv..."

    # Check system uv
    $systemUv = Get-Command uv -ErrorAction SilentlyContinue
    if ($systemUv) {
        $ver = Get-UvVersion $systemUv.Source
        if ($ver -and $ver -ge $MinUvVersion) {
            $script:UvPath = $systemUv.Source
            Write-Ok "Using system uv: $($script:UvPath)"
            return
        }
    }

    # Check local uv
    $localUv = Join-Path $BinDir "uv.exe"
    if (Test-Path $localUv) {
        $ver = Get-UvVersion $localUv
        if ($ver -and $ver -ge $MinUvVersion) {
            $script:UvPath = $localUv
            Write-Ok "Using local uv: $($script:UvPath)"
            return
        }
    }

    # Download uv
    Write-Info "Downloading uv..."
    $target = "x86_64-pc-windows-msvc"

    if ($UvVersion -eq "latest") {
        $url = "https://github.com/astral-sh/uv/releases/latest/download/uv-${target}.zip"
    } else {
        $url = "https://github.com/astral-sh/uv/releases/download/${UvVersion}/uv-${target}.zip"
    }

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "uv-download.zip"
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "uv-extract"

    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpFile -UseBasicParsing
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        Expand-Archive -Path $tmpFile -DestinationPath $tmpDir -Force

        # Find uv.exe in extracted contents
        $uvExe = Get-ChildItem -Path $tmpDir -Recurse -Filter "uv.exe" | Select-Object -First 1
        if (-not $uvExe) { Stop-WithError "uv.exe not found in archive" }
        Copy-Item $uvExe.FullName (Join-Path $BinDir "uv.exe") -Force
    } finally {
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $script:UvPath = Join-Path $BinDir "uv.exe"
    Write-Ok "uv installed: $($script:UvPath) ($(& $script:UvPath --version))"
}

# ─── Python ──────────────────────────────────────────────────

function Ensure-Python {
    Write-Info "Ensuring Python ${PythonVersion}..."

    $env:UV_PYTHON_INSTALL_DIR = $PythonDir

    # Check if Python is already available via uv
    try {
        $result = & $script:UvPath python find $PythonVersion 2>$null
        if ($LASTEXITCODE -eq 0 -and $result) {
            Write-Ok "Python ${PythonVersion} already available: $($result.Trim())"
            return
        }
    } catch {}

    # Install Python via uv
    Write-Info "Installing Python ${PythonVersion} via uv..."
    New-Item -ItemType Directory -Path $PythonDir -Force | Out-Null
    & $script:UvPath python install $PythonVersion
    if ($LASTEXITCODE -ne 0) { Stop-WithError "uv python install failed" }
    Write-Ok "Python ${PythonVersion} installed"
}

# ─── Python venv ─────────────────────────────────────────────

function Setup-Venv {
    Write-Info "Setting up Python venv..."

    $venvPython = Join-Path $VenvDir "Scripts" "python.exe"
    if (Test-Path $venvPython) {
        Write-Ok "Venv already exists: $VenvDir"
        return
    }

    $env:UV_PYTHON_INSTALL_DIR = $PythonDir
    & $script:UvPath venv $VenvDir --python $PythonVersion --seed
    if ($LASTEXITCODE -ne 0) { Stop-WithError "uv venv failed" }
    Write-Ok "Venv created: $VenvDir (with pip)"
}

# ─── fnm ─────────────────────────────────────────────────────

function Resolve-Fnm {
    Write-Info "Resolving fnm..."

    # Check system fnm
    $systemFnm = Get-Command fnm -ErrorAction SilentlyContinue
    if ($systemFnm) {
        $script:FnmPath = $systemFnm.Source
        Write-Ok "Using system fnm: $($script:FnmPath)"
        return
    }

    # Check local fnm
    $localFnm = Join-Path $BinDir "fnm.exe"
    if (Test-Path $localFnm) {
        $script:FnmPath = $localFnm
        Write-Ok "Using local fnm: $($script:FnmPath)"
        return
    }

    # Download fnm
    Write-Info "Downloading fnm..."
    $asset = "fnm-windows.zip"

    if ($FnmVersion -eq "latest") {
        $url = "https://github.com/Schniz/fnm/releases/latest/download/${asset}"
    } else {
        $url = "https://github.com/Schniz/fnm/releases/download/${FnmVersion}/${asset}"
    }

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "fnm-download.zip"
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "fnm-extract"

    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpFile -UseBasicParsing
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        Expand-Archive -Path $tmpFile -DestinationPath $tmpDir -Force

        $fnmExe = Get-ChildItem -Path $tmpDir -Recurse -Filter "fnm.exe" | Select-Object -First 1
        if (-not $fnmExe) { Stop-WithError "fnm.exe not found in archive" }
        Copy-Item $fnmExe.FullName (Join-Path $BinDir "fnm.exe") -Force
    } finally {
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $script:FnmPath = Join-Path $BinDir "fnm.exe"
    Write-Ok "fnm installed: $($script:FnmPath) ($(& $script:FnmPath --version))"
}

# ─── Node.js ─────────────────────────────────────────────────

function Ensure-Node {
    Write-Info "Ensuring Node.js v${NodeVersion}..."

    # Check system node first
    $systemNode = Get-Command node -ErrorAction SilentlyContinue
    if ($systemNode) {
        $major = Get-NodeMajor $systemNode.Source
        if ($major -and $major -ge $MinNodeMajor) {
            Write-Ok "System Node.js is sufficient: v$major"
            return
        }
        Write-Info "System Node.js (v$major) is too old, installing via fnm..."
    }

    # Install via fnm
    New-Item -ItemType Directory -Path $FnmDir -Force | Out-Null
    $env:FNM_DIR = $FnmDir
    & $script:FnmPath install $NodeVersion
    if ($LASTEXITCODE -ne 0) { Stop-WithError "fnm install failed" }

    Write-Ok "Node.js v${NodeVersion} installed via fnm"
}

# ─── Environment File Generation ─────────────────────────────

function New-EnvFiles {
    Write-Info "Generating env.ps1..."

    $envPs1 = @'
# agent-environment: dot-source this file to activate the agent runtime.
# Usage: . ~/.agents/env.ps1

$env:AGENTS_HOME = if ($env:AGENTS_HOME) { $env:AGENTS_HOME } else { Join-Path $HOME ".agents" }
$env:PATH = "$env:AGENTS_HOME\venv\Scripts;$env:AGENTS_HOME\bin;$env:PATH"
$env:UV_PYTHON_INSTALL_DIR = "$env:AGENTS_HOME\python"
$env:FNM_DIR = "$env:AGENTS_HOME\fnm"

# Activate fnm-managed Node.js if fnm is available
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env | Out-String | Invoke-Expression
}
'@

    Set-Content -Path (Join-Path $AgentsHome "env.ps1") -Value $envPs1 -Encoding UTF8
    Write-Ok "Generated $(Join-Path $AgentsHome 'env.ps1')"
}

# ─── PowerShell Profile Patching ─────────────────────────────

function Update-ShellProfile {
    $sourceLine = ". `"$(Join-Path $AgentsHome 'env.ps1')`""
    $marker = "# agent-environment"
    $profilePath = $PROFILE.CurrentUserAllHosts

    # Create profile directory if it doesn't exist
    $profileDir = Split-Path $profilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Check if already patched
    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
        if ($content -and $content.Contains($marker)) {
            Write-Info "Already configured in $profilePath"
            return
        }
    }

    # Append source line
    Add-Content -Path $profilePath -Value "`n$marker`n$sourceLine"
    Write-Ok "Added to $profilePath"
    Write-Info "Run '. $profilePath' or restart your terminal to activate."
}

# ─── Main ────────────────────────────────────────────────────

function Main {
    Write-Host ""
    Write-Info "agent-environment installer"
    Write-Info "Install root: $AgentsHome"
    Write-Host ""

    Write-Info "Platform: windows-x86_64"
    Write-Host ""

    New-Item -ItemType Directory -Path $AgentsHome -Force | Out-Null

    # Step 1: uv
    Resolve-Uv
    Write-Host ""

    # Step 2: Python
    Ensure-Python
    Write-Host ""

    # Step 3: Python venv
    Setup-Venv
    Write-Host ""

    # Step 4: fnm
    Resolve-Fnm
    Write-Host ""

    # Step 5: Node.js
    Ensure-Node
    Write-Host ""

    # Step 5: Generate env files
    New-EnvFiles
    Write-Host ""

    # Step 6: Patch shell profile
    Update-ShellProfile
    Write-Host ""

    Write-Ok "All done! Agent runtime environment is ready."
    Write-Info "  AGENTS_HOME = $AgentsHome"
    Write-Info "  uv          = $($script:UvPath)"
    Write-Info "  fnm         = $($script:FnmPath)"
    Write-Host ""
}

Main
