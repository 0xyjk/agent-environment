# agent-environment

Self-contained installer for agent runtime environments. Installs **uv**, **Python**, **fnm**, and **Node.js** with a single command.

## Quick Start

**macOS / Linux:**

```sh
# Clone and run
git clone https://github.com/0xyjk/agent-environment.git
sh agent-environment/install.sh

# Or pipe install
curl -fsSL https://raw.githubusercontent.com/0xyjk/agent-environment/main/install.sh | sh
```

**Windows (PowerShell):**

```powershell
# Clone and run
git clone https://github.com/0xyjk/agent-environment.git
pwsh agent-environment/install.ps1

# Or pipe install
irm https://raw.githubusercontent.com/0xyjk/agent-environment/main/install.ps1 | iex
```

## What Gets Installed

| Tool | Purpose | Install Method |
|------|---------|----------------|
| [uv](https://github.com/astral-sh/uv) | Python package manager | Direct binary download |
| Python 3.12 | Python runtime | Via `uv python install` |
| [fnm](https://github.com/Schniz/fnm) | Node.js version manager | Direct binary download |
| Node.js 20 | JavaScript runtime | Via `fnm install` |

All tools are installed to `~/.agents/` by default. The installer is **idempotent** — running it again skips already-installed tools.

## Configuration

Override defaults with environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENTS_HOME` | `~/.agents` | Install root directory |
| `AGENTS_UV_VERSION` | `latest` | uv version (`latest` or e.g. `0.7.1`) |
| `AGENTS_PYTHON_VERSION` | `3.12` | Python version |
| `AGENTS_FNM_VERSION` | `latest` | fnm version (`latest` or e.g. `v1.38.0`) |
| `AGENTS_NODE_VERSION` | `20` | Node.js major version |

Example:

```sh
AGENTS_HOME=/opt/agents AGENTS_PYTHON_VERSION=3.13 sh install.sh
```

## Directory Layout

After installation:

```
~/.agents/
├── bin/
│   ├── uv              # uv binary
│   └── fnm             # fnm binary
├── python/             # uv-managed Python installations
├── fnm/                # fnm-managed Node.js versions
│   └── node-versions/
├── env.sh              # Source this to activate (Unix)
└── env.ps1             # Dot-source this to activate (Windows)
```

## Shell Integration

The installer automatically adds a source line to your shell profile (`.zshrc`, `.bashrc`, `.bash_profile`, or PowerShell `$PROFILE`). After installation, restart your terminal or run:

```sh
source ~/.agents/env.sh        # Unix
. ~/.agents/env.ps1            # PowerShell
```

## Project Files

```
agent-environment/
├── install.sh       # Unix install script
├── install.ps1      # Windows install script
├── uninstall.sh     # Unix uninstall script
├── uninstall.ps1    # Windows uninstall script
├── .gitignore
└── README.md
```

## Uninstall

**macOS / Linux:**

```sh
sh uninstall.sh
```

**Windows (PowerShell):**

```powershell
pwsh uninstall.ps1
```

This removes only the files created by the installer (`bin/`, `python/`, `fnm/`, `env.sh`, `env.ps1`) and cleans the shell profile. Other files in `$AGENTS_HOME` are left untouched. If `$AGENTS_HOME` is empty after cleanup, it is removed automatically.

## Resolution Strategy

For each tool, the installer follows this priority:

1. **System binary** — if already on `PATH` and version is sufficient, use it
2. **Local binary** — if previously downloaded to `$AGENTS_HOME/bin/`, use it
3. **Download** — fetch from GitHub releases as a last resort

## License

MIT
