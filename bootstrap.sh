#!/bin/bash
# Compatible with Bash 3.2 (macOS default)

set -euo pipefail

# Color output (Bash 3.2 compatible)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

log() {
    echo "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo "${RED}[ERROR]${NC} $1" >&2
}

# Configuration
REPO_URL="https://github.com/simonclausen/mac-setup.git"
SETUP_DIR="$HOME/.mac-setup"

log "macOS Setup Bootstrapper"
log "========================"

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    error "This script is designed for macOS only"
    exit 1
fi

# Install Xcode Command Line Tools (includes git!)
if ! xcode-select -p > /dev/null 2>&1; then
    log "Installing Xcode Command Line Tools (this includes git)..."
    
    # This will prompt for installation
    xcode-select --install
    
    # Wait for user to complete installation
    echo "Press enter when Xcode Command Line Tools installation is complete..."
    read -r
    
    # Verify installation
    if ! xcode-select -p > /dev/null 2>&1; then
        error "Xcode Command Line Tools installation failed"
        exit 1
    fi
fi

# Now we have git!
log "Git is now available: $(git --version)"

# Allow passing flags through to install.sh (e.g. --dry-run)
INSTALL_ARGS=("$@")

# Clone or update the setup repository (idempotent)
if [[ -d "$SETUP_DIR/.git" ]]; then
    cd "$SETUP_DIR"
    # Only pull if remote HEAD moved
    LOCAL_HEAD=$(git rev-parse HEAD || echo unknown)
    git remote update >/dev/null 2>&1 || true
    REMOTE_HEAD=$(git rev-parse @{u} 2>/dev/null || echo unknown)
    if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" && "$REMOTE_HEAD" != unknown ]]; then
        log "Updating repository (git pull)"
        git pull --ff-only || git pull
    else
        log "Repository already up-to-date"
    fi
else
    log "Cloning setup repository into $SETUP_DIR"
    git clone "$REPO_URL" "$SETUP_DIR"
    cd "$SETUP_DIR"
fi

# Make scripts executable
chmod +x install.sh
chmod +x macos-defaults.sh

# Run the main installation
log "Starting main installation (passing args: ${INSTALL_ARGS[*]:-none})..."
./install.sh "${INSTALL_ARGS[@]}"

log "Bootstrap complete!"