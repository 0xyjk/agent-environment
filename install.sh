#!/usr/bin/env sh
# agent-environment installer
# Installs uv, Python, fnm, and Node.js into a self-contained directory.
#
# Usage:
#   sh install.sh
#   curl -fsSL https://raw.githubusercontent.com/0xyjk/agent-environment/main/install.sh | sh
#
# Environment variables:
#   AGENTS_HOME            - Install root (default: ~/.agents)
#   AGENTS_UV_VERSION      - uv version to install (default: latest)
#   AGENTS_PYTHON_VERSION  - Python version (default: 3.12)
#   AGENTS_FNM_VERSION     - fnm version to install (default: latest)
#   AGENTS_NODE_VERSION    - Node.js major version (default: 20)

set -eu

# ─── Configuration ────────────────────────────────────────────

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
AGENTS_UV_VERSION="${AGENTS_UV_VERSION:-latest}"
AGENTS_PYTHON_VERSION="${AGENTS_PYTHON_VERSION:-3.12}"
AGENTS_FNM_VERSION="${AGENTS_FNM_VERSION:-latest}"
AGENTS_NODE_VERSION="${AGENTS_NODE_VERSION:-20}"

MIN_UV_VERSION="0.6.0"
MIN_NODE_MAJOR="20"

BIN_DIR="$AGENTS_HOME/bin"
PYTHON_DIR="$AGENTS_HOME/python"
VENV_DIR="$AGENTS_HOME/venv"
FNM_DIR="$AGENTS_HOME/fnm"

# ─── Output Helpers ───────────────────────────────────────────

if [ -t 2 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    RESET=''
fi

info()  { printf "${BLUE}[info]${RESET}  %s\n" "$*" >&2; }
ok()    { printf "${GREEN}[ok]${RESET}    %s\n" "$*" >&2; }
warn()  { printf "${YELLOW}[warn]${RESET}  %s\n" "$*" >&2; }
error() { printf "${RED}[error]${RESET} %s\n" "$*" >&2; }
die()   { error "$@"; exit 1; }

# ─── Platform Detection ──────────────────────────────────────

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux*)  OS="linux" ;;
        Darwin*) OS="macos" ;;
        *)       die "Unsupported OS: $OS" ;;
    esac

    case "$ARCH" in
        x86_64|amd64)  ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        *)             die "Unsupported architecture: $ARCH" ;;
    esac
}

# ─── Download Helper ─────────────────────────────────────────

# download URL DEST_FILE
download() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    else
        die "Neither curl nor wget found. Please install one of them."
    fi
}

# ─── Version Comparison ──────────────────────────────────────

# version_gte VERSION MIN_VERSION
# Returns 0 (true) if VERSION >= MIN_VERSION using simple semver comparison.
version_gte() {
    ver="$1"
    min="$2"

    # Extract major.minor.patch
    ver_major="$(echo "$ver" | cut -d. -f1)"
    ver_minor="$(echo "$ver" | cut -d. -f2)"
    ver_patch="$(echo "$ver" | cut -d. -f3 | cut -d- -f1 | cut -d+ -f1)"

    min_major="$(echo "$min" | cut -d. -f1)"
    min_minor="$(echo "$min" | cut -d. -f2)"
    min_patch="$(echo "$min" | cut -d. -f3 | cut -d- -f1 | cut -d+ -f1)"

    # Default empty to 0
    ver_major="${ver_major:-0}"
    ver_minor="${ver_minor:-0}"
    ver_patch="${ver_patch:-0}"
    min_major="${min_major:-0}"
    min_minor="${min_minor:-0}"
    min_patch="${min_patch:-0}"

    if [ "$ver_major" -gt "$min_major" ] 2>/dev/null; then return 0; fi
    if [ "$ver_major" -lt "$min_major" ] 2>/dev/null; then return 1; fi
    if [ "$ver_minor" -gt "$min_minor" ] 2>/dev/null; then return 0; fi
    if [ "$ver_minor" -lt "$min_minor" ] 2>/dev/null; then return 1; fi
    if [ "$ver_patch" -ge "$min_patch" ] 2>/dev/null; then return 0; fi
    return 1
}

# ─── uv ──────────────────────────────────────────────────────

# Parse version from "uv X.Y.Z" or "uv X.Y.Z (hash)" output.
parse_uv_version() {
    echo "$1" | sed -n 's/^uv \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p'
}

check_uv() {
    uv_bin="$1"
    if [ ! -x "$uv_bin" ] 2>/dev/null && ! command -v "$uv_bin" >/dev/null 2>&1; then
        return 1
    fi
    ver_output="$("$uv_bin" --version 2>/dev/null)" || return 1
    ver="$(parse_uv_version "$ver_output")"
    [ -n "$ver" ] && version_gte "$ver" "$MIN_UV_VERSION"
}

get_uv_target() {
    case "${OS}-${ARCH}" in
        macos-aarch64)  echo "aarch64-apple-darwin" ;;
        macos-x86_64)   echo "x86_64-apple-darwin" ;;
        linux-x86_64)   echo "x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  echo "aarch64-unknown-linux-gnu" ;;
        *)              die "Unsupported platform for uv: ${OS}-${ARCH}" ;;
    esac
}

resolve_uv() {
    info "Resolving uv..."

    # Check system uv
    if command -v uv >/dev/null 2>&1 && check_uv "uv"; then
        UV_PATH="$(command -v uv)"
        ok "Using system uv: $UV_PATH"
        return
    fi

    # Check local uv
    if check_uv "$BIN_DIR/uv"; then
        UV_PATH="$BIN_DIR/uv"
        ok "Using local uv: $UV_PATH"
        return
    fi

    # Download uv
    info "Downloading uv..."
    target="$(get_uv_target)"

    if [ "$AGENTS_UV_VERSION" = "latest" ]; then
        url="https://github.com/astral-sh/uv/releases/latest/download/uv-${target}.tar.gz"
    else
        url="https://github.com/astral-sh/uv/releases/download/${AGENTS_UV_VERSION}/uv-${target}.tar.gz"
    fi

    mkdir -p "$BIN_DIR"
    tmpfile="$(mktemp)"
    trap 'rm -f "$tmpfile"' EXIT
    download "$url" "$tmpfile"

    tar -xzf "$tmpfile" -C "$BIN_DIR" --strip-components=1
    chmod +x "$BIN_DIR/uv"
    rm -f "$tmpfile"

    UV_PATH="$BIN_DIR/uv"
    ok "uv installed: $UV_PATH ($("$UV_PATH" --version))"
}

# ─── Python ──────────────────────────────────────────────────

ensure_python() {
    info "Ensuring Python ${AGENTS_PYTHON_VERSION}..."

    # Check if Python is already available via uv
    if "$UV_PATH" python find "$AGENTS_PYTHON_VERSION" >/dev/null 2>&1; then
        python_path="$("$UV_PATH" python find "$AGENTS_PYTHON_VERSION" 2>/dev/null)"
        ok "Python ${AGENTS_PYTHON_VERSION} already available: $python_path"
        return
    fi

    # Install Python via uv
    info "Installing Python ${AGENTS_PYTHON_VERSION} via uv..."
    mkdir -p "$PYTHON_DIR"
    UV_PYTHON_INSTALL_DIR="$PYTHON_DIR" "$UV_PATH" python install "$AGENTS_PYTHON_VERSION"
    ok "Python ${AGENTS_PYTHON_VERSION} installed"
}

# ─── Python venv ─────────────────────────────────────────────

setup_venv() {
    info "Setting up Python venv..."

    venv_python="$VENV_DIR/bin/python"
    if [ -x "$venv_python" ]; then
        ok "Venv already exists: $VENV_DIR"
        return
    fi

    UV_PYTHON_INSTALL_DIR="$PYTHON_DIR" "$UV_PATH" venv "$VENV_DIR" \
        --python "$AGENTS_PYTHON_VERSION" --seed
    ok "Venv created: $VENV_DIR (with pip)"
}

# ─── fnm ─────────────────────────────────────────────────────

get_fnm_asset() {
    case "$OS" in
        macos)  echo "fnm-macos.zip" ;;
        linux)
            case "$ARCH" in
                x86_64)  echo "fnm-linux.zip" ;;
                aarch64) echo "fnm-arm64.zip" ;;
                *)       die "Unsupported architecture for fnm: $ARCH" ;;
            esac
            ;;
        *)      die "Unsupported OS for fnm: $OS" ;;
    esac
}

resolve_fnm() {
    info "Resolving fnm..."

    # Check system fnm
    if command -v fnm >/dev/null 2>&1; then
        FNM_PATH="$(command -v fnm)"
        ok "Using system fnm: $FNM_PATH"
        return
    fi

    # Check local fnm
    if [ -x "$BIN_DIR/fnm" ]; then
        FNM_PATH="$BIN_DIR/fnm"
        ok "Using local fnm: $FNM_PATH"
        return
    fi

    # Download fnm
    info "Downloading fnm..."
    asset="$(get_fnm_asset)"

    if [ "$AGENTS_FNM_VERSION" = "latest" ]; then
        url="https://github.com/Schniz/fnm/releases/latest/download/${asset}"
    else
        url="https://github.com/Schniz/fnm/releases/download/${AGENTS_FNM_VERSION}/${asset}"
    fi

    mkdir -p "$BIN_DIR"
    tmpfile="$(mktemp)"
    download "$url" "$tmpfile"

    # fnm releases are zip archives
    if ! command -v unzip >/dev/null 2>&1; then
        die "unzip is required to extract fnm. Please install it."
    fi
    unzip -o -q "$tmpfile" -d "$BIN_DIR"
    chmod +x "$BIN_DIR/fnm"
    rm -f "$tmpfile"

    FNM_PATH="$BIN_DIR/fnm"
    ok "fnm installed: $FNM_PATH ($("$FNM_PATH" --version))"
}

# ─── Node.js ─────────────────────────────────────────────────

parse_node_major() {
    echo "$1" | sed -n 's/^v\([0-9][0-9]*\)\..*/\1/p'
}

ensure_node() {
    info "Ensuring Node.js v${AGENTS_NODE_VERSION}..."

    # Check system node first
    if command -v node >/dev/null 2>&1; then
        node_ver="$(node --version 2>/dev/null)" || true
        node_major="$(parse_node_major "$node_ver")"
        if [ -n "$node_major" ] && [ "$node_major" -ge "$MIN_NODE_MAJOR" ] 2>/dev/null; then
            ok "System Node.js is sufficient: $node_ver"
            return
        fi
        info "System Node.js ($node_ver) is too old, installing via fnm..."
    fi

    # Install via fnm
    mkdir -p "$FNM_DIR"
    FNM_DIR="$FNM_DIR" "$FNM_PATH" install "$AGENTS_NODE_VERSION"
    FNM_DIR="$FNM_DIR" "$FNM_PATH" default "$AGENTS_NODE_VERSION"

    # Verify
    node_bin="$(FNM_DIR="$FNM_DIR" "$FNM_PATH" exec --using="$AGENTS_NODE_VERSION" -- which node 2>/dev/null)" || true
    if [ -n "$node_bin" ]; then
        ok "Node.js installed: $("$node_bin" --version)"
    else
        ok "Node.js v${AGENTS_NODE_VERSION} installed via fnm"
    fi
}

# ─── Environment File Generation ─────────────────────────────

generate_env() {
    info "Generating env.sh..."

    cat > "$AGENTS_HOME/env.sh" << 'ENVEOF'
# agent-environment: source this file to activate the agent runtime.
# Usage: . ~/.agents/env.sh

export AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
export PATH="$AGENTS_HOME/venv/bin:$AGENTS_HOME/bin:$PATH"
export UV_PYTHON_INSTALL_DIR="$AGENTS_HOME/python"
export FNM_DIR="$AGENTS_HOME/fnm"

# Activate fnm-managed Node.js if fnm is available
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env)"
fi
ENVEOF

    ok "Generated $AGENTS_HOME/env.sh"
}

# ─── Shell Profile Patching ──────────────────────────────────

patch_shell_profile() {
    source_line=". \"$AGENTS_HOME/env.sh\""
    marker="# agent-environment"

    # Determine which profile files to patch
    profiles=""

    case "$(basename "${SHELL:-}")" in
        zsh)
            profiles="$HOME/.zshrc"
            ;;
        bash)
            if [ "$OS" = "macos" ]; then
                profiles="$HOME/.bash_profile"
            else
                profiles="$HOME/.bashrc"
            fi
            ;;
        *)
            # Try common profiles
            if [ -f "$HOME/.zshrc" ]; then
                profiles="$HOME/.zshrc"
            elif [ -f "$HOME/.bashrc" ]; then
                profiles="$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                profiles="$HOME/.bash_profile"
            else
                profiles="$HOME/.profile"
            fi
            ;;
    esac

    for profile in $profiles; do
        # Check if already patched
        if [ -f "$profile" ] && grep -qF "$marker" "$profile" 2>/dev/null; then
            info "Already configured in $profile"
            continue
        fi

        # Append source line
        printf '\n%s\n%s\n' "$marker" "$source_line" >> "$profile"
        ok "Added to $profile"
        info "Run 'source $profile' or restart your terminal to activate."
    done
}

# ─── Main ────────────────────────────────────────────────────

main() {
    printf "\n"
    info "agent-environment installer"
    info "Install root: $AGENTS_HOME"
    printf "\n"

    detect_platform
    info "Platform: ${OS}-${ARCH}"
    printf "\n"

    mkdir -p "$AGENTS_HOME"

    # Step 1: uv
    resolve_uv
    printf "\n"

    # Step 2: Python
    ensure_python
    printf "\n"

    # Step 3: Python venv
    setup_venv
    printf "\n"

    # Step 4: fnm
    resolve_fnm
    printf "\n"

    # Step 5: Node.js
    ensure_node
    printf "\n"

    # Step 6: Generate env file
    generate_env
    printf "\n"

    # Step 7: Patch shell profile
    patch_shell_profile
    printf "\n"

    ok "All done! Agent runtime environment is ready."
    info "  AGENTS_HOME = $AGENTS_HOME"
    info "  uv          = $UV_PATH"
    info "  fnm         = $FNM_PATH"
    printf "\n"

    # Activate environment in current session
    . "$AGENTS_HOME/env.sh"
    info "Environment activated in current session."
}

main "$@"
