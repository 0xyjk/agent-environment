#!/usr/bin/env sh
# agent-environment uninstaller
# Removes tools installed by install.sh without touching other files in AGENTS_HOME.
#
# Usage:
#   sh uninstall.sh

set -eu

# ─── Configuration ────────────────────────────────────────────

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"

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

# ─── Platform Detection ──────────────────────────────────────

OS="$(uname -s)"
case "$OS" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="macos" ;;
esac

# ─── Remove Installed Files ──────────────────────────────────

remove_dir() {
    if [ -d "$1" ]; then
        rm -rf "$1"
        ok "Removed $1"
    fi
}

remove_file() {
    if [ -f "$1" ]; then
        rm -f "$1"
        ok "Removed $1"
    fi
}

remove_installed_files() {
    info "Removing installed files from $AGENTS_HOME..."

    remove_dir  "$AGENTS_HOME/bin"
    remove_dir  "$AGENTS_HOME/python"
    remove_dir  "$AGENTS_HOME/fnm"
    remove_file "$AGENTS_HOME/env.sh"
    remove_file "$AGENTS_HOME/env.ps1"

    # Remove AGENTS_HOME if empty
    if [ -d "$AGENTS_HOME" ]; then
        if [ -z "$(ls -A "$AGENTS_HOME" 2>/dev/null)" ]; then
            rmdir "$AGENTS_HOME"
            ok "Removed empty directory $AGENTS_HOME"
        else
            info "$AGENTS_HOME still contains other files, keeping it."
        fi
    fi
}

# ─── Clean Shell Profile ─────────────────────────────────────

clean_profile() {
    profile="$1"
    [ -f "$profile" ] || return 0

    marker="# agent-environment"

    if ! grep -qF "$marker" "$profile" 2>/dev/null; then
        return 0
    fi

    # Remove the marker line and the line immediately after it
    tmpfile="$(mktemp)"
    skip_next=0
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skip_next" = 1 ]; then
            skip_next=0
            continue
        fi
        case "$line" in
            *"$marker"*)
                skip_next=1
                continue
                ;;
        esac
        printf '%s\n' "$line"
    done < "$profile" > "$tmpfile"

    cp "$tmpfile" "$profile"
    rm -f "$tmpfile"

    ok "Cleaned $profile"
}

clean_shell_profiles() {
    info "Cleaning shell profiles..."

    case "$(basename "${SHELL:-}")" in
        zsh)
            clean_profile "$HOME/.zshrc"
            ;;
        bash)
            if [ "$OS" = "macos" ]; then
                clean_profile "$HOME/.bash_profile"
            else
                clean_profile "$HOME/.bashrc"
            fi
            ;;
        *)
            # Try all common profiles
            clean_profile "$HOME/.zshrc"
            clean_profile "$HOME/.bashrc"
            clean_profile "$HOME/.bash_profile"
            clean_profile "$HOME/.profile"
            ;;
    esac
}

# ─── Main ────────────────────────────────────────────────────

main() {
    printf "\n"
    info "agent-environment uninstaller"
    info "AGENTS_HOME: $AGENTS_HOME"
    printf "\n"

    remove_installed_files
    printf "\n"

    clean_shell_profiles
    printf "\n"

    ok "Uninstall complete. Restart your terminal to apply changes."
    printf "\n"
}

main "$@"
