#!/usr/bin/env bash
# install.sh — One-command brana installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/martineserios/thebrana/main/install.sh | bash
#
#   # Custom install dir:
#   curl -fsSL .../install.sh | BRANA_DIR=~/my-brana bash
#
#   # From inside a cloned repo:
#   ./install.sh
#
#   # Update an existing install:
#   ./install.sh          (re-runs bootstrap, pulls latest)
#   BRANA_DIR=~/brana bash install.sh

set -euo pipefail

REPO="https://github.com/martineserios/thebrana.git"
BRANA_DIR="${BRANA_DIR:-$HOME/brana}"

# ANSI colors (suppressed when not a TTY)
if [ -t 1 ]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; NC=''
fi

info()  { echo -e "${GREEN}[brana]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()   { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# --- Prerequisites ---
check_prereqs() {
    info "Checking prerequisites..."
    command -v git >/dev/null 2>&1 || die "git not found. Install git and retry."
    command -v jq  >/dev/null 2>&1 || warn "jq not found — hook wiring limited. Install jq for full functionality."
    command -v node >/dev/null 2>&1 \
        || warn "Node.js not found — cross-session memory (ruflo) disabled. Install Node.js v20+ to enable."
}

# --- Clone or update ---
setup_repo() {
    if [ -f "${SCRIPT_DIR}/bootstrap.sh" ]; then
        # Running from inside an existing clone
        BRANA_DIR="$SCRIPT_DIR"
        info "Using existing repo at $BRANA_DIR"
        return
    fi

    if [ -d "$BRANA_DIR/.git" ]; then
        info "Updating existing install at $BRANA_DIR..."
        git -C "$BRANA_DIR" pull --ff-only \
            || warn "git pull failed — continuing with current version."
    else
        info "Cloning brana to $BRANA_DIR..."
        git clone "$REPO" "$BRANA_DIR"
    fi
}

# --- Bootstrap ---
run_bootstrap() {
    info "Running bootstrap..."
    cd "$BRANA_DIR"
    bash bootstrap.sh
}

# --- Done ---
print_success() {
    echo ""
    echo -e "${GREEN}=== brana installed ===${NC}"
    echo ""
    echo "  Location:  $BRANA_DIR"
    echo "  Plugin:    registered — auto-loads in Claude Code"
    echo ""
    echo "  Start a new Claude Code session in any project directory."
    echo "  Skills load automatically. Run /brana:build to get started."
    echo ""
    echo "  Docs:  $BRANA_DIR/docs/guide/getting-started.md"
    echo ""
}

# Detect if called as ./install.sh from inside the repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd || echo "")"

check_prereqs
setup_repo
run_bootstrap
print_success
