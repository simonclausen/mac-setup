#!/usr/bin/env bash

set -euo pipefail

################################################################################
# Idempotent macOS development environment installer
# Features:
#  - Safe re-runs (avoids duplicate PATH/lines)
#  - Optional dry-run mode
#  - Modular .zshrc.d configuration fragments
#  - Brewfile integrity check before install
#  - GNU tools precedence setup (configurable)
#  - Optional sections controllable via flags
#  - Graceful handling of SSH-based taps on first setup
################################################################################

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

START_TIME_EPOCH=$(date +%s)

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

abort() { error "$1"; exit 1; }

# Defaults for feature toggles
DO_BREW_UPDATE=1
DO_BUNDLE=1
DO_INTERNAL_BUNDLE=1
DO_GNU=1
DO_DEFAULTS=1
DO_OHMYZSH=1
DO_MISE=1
DO_MISE_INSTALL=1
DO_GIT_CONFIG=1
DO_DOTFILES=1
DO_AWS_SAML=1
DRY_RUN=0
VERBOSE=0

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
    --dry-run             Show what would happen without executing changes
    --no-brew-update      Skip 'brew update'
    --no-bundle           Skip all Brewfile bundle phases
    --no-internal-bundle  Skip internal/full Brewfile phase
    --no-gnu              Skip GNU tools PATH precedence setup
    --no-defaults         Skip applying macOS defaults
    --no-ohmyzsh          Skip Oh My Zsh installation
    --no-mise             Skip mise activation/install & tool installation
    --no-mise-install     Activate mise but skip 'mise install'
    --no-git-config       Skip git config provisioning
    --no-dotfiles         Skip generic dotfiles/ provisioning (except .gitconfig already controlled by --no-git-config)
    --no-aws-saml         Skip AWS SAML role (saml2aws) helper configuration
    --verbose             More verbose output
    -h, --help            Show this help and exit

Re-runnable & idempotent. Exit code non-zero on failure.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --no-brew-update) DO_BREW_UPDATE=0 ;;
    --no-bundle) DO_BUNDLE=0; DO_INTERNAL_BUNDLE=0 ;;
    --no-internal-bundle) DO_INTERNAL_BUNDLE=0 ;;
        --no-gnu) DO_GNU=0 ;;
        --no-defaults) DO_DEFAULTS=0 ;;
        --no-ohmyzsh) DO_OHMYZSH=0 ;;
        --no-mise) DO_MISE=0 DO_MISE_INSTALL=0 ;;
        --no-mise-install) DO_MISE_INSTALL=0 ;;
        --no-git-config) DO_GIT_CONFIG=0 ;;
    --no-dotfiles) DO_DOTFILES=0 ;;
    --no-aws-saml) DO_AWS_SAML=0 ;;
        --verbose) VERBOSE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) abort "Unknown option: $1" ;;
    esac
    shift
done

run() {
    if (( DRY_RUN )); then
        echo "DRY-RUN: $*"; return 0
    fi
    if (( VERBOSE )); then
        set -x
        "$@"
        local rc=$?
        set +x
        return $rc
    else
        "$@"
    fi
}

append_unique_line() {
    local file="$1"; shift
    local line="$*"
    [[ -f "$file" ]] || touch "$file"
    grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

ensure_dir() { [[ -d "$1" ]] || run mkdir -p "$1"; }

# Pre-flight checks
[[ "$OSTYPE" == darwin* ]] || abort "This script is macOS-only. OSTYPE=$OSTYPE"
[[ $EUID -ne 0 ]] || abort "Do not run as root. Use your normal user (sudo will be invoked as needed)."

# Sudo keep-alive (needed for macOS defaults + brew operations that prompt)
if (( ! DRY_RUN )); then
    if command -v sudo >/dev/null 2>&1; then
        sudo -v || abort "sudo authorization failed"
        # Keep alive in background while script runs
        ( while true; do sleep 60; sudo -n true 2>/dev/null || exit; done ) &
        SUDO_KEEPALIVE_PID=$!
        trap '[[ ${SUDO_KEEPALIVE_PID:-0} -gt 0 ]] && kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT
    fi
fi

log "Starting macOS development environment setup"
(( DRY_RUN )) && warn "Running in DRY-RUN mode - no changes will be applied."

ARCH=$(uname -m)
BREW_BIN="/opt/homebrew/bin/brew"
if [[ "$ARCH" == "x86_64" ]]; then
    # On Intel macs default prefix historically /usr/local
    [[ -x /usr/local/bin/brew ]] && BREW_BIN="/usr/local/bin/brew"
fi

install_xcode_clt() {
    if xcode-select -p &>/dev/null; then
        info "Xcode Command Line Tools already installed"
        return 0
    fi
    log "Installing Xcode Command Line Tools (one-time)"
    if (( DRY_RUN )); then
        echo "DRY-RUN: xcode-select --install"
        return 0
    fi
    xcode-select --install || true
    # Wait until installed (user may need to confirm GUI dialog)
    local tries=0
    until xcode-select -p &>/dev/null; do
        (( tries++ ))
        if (( tries > 120 )); then
            abort "Timeout waiting for Xcode CLT (waited >10m)"
        fi
        sleep 5
    done
    info "Xcode CLT installation detected"
}

install_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        info "Homebrew already installed: $(brew --version | head -n1)"
        if (( DO_BREW_UPDATE )); then
            log "Updating Homebrew (can be skipped with --no-brew-update)"
            run brew update
        else
            info "Skipping brew update (flag)"
        fi
        return 0
    fi
    log "Installing Homebrew..."
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # shellenv lines
    if [[ -x "$BREW_BIN" ]]; then
        local shellenv_cmd
        shellenv_cmd="$($BREW_BIN shellenv)"
        # Put into .zprofile (login shells) and modular file
        append_unique_line "$HOME/.zprofile" "eval \"$($BREW_BIN shellenv)\""
        ensure_dir "$HOME/.zshrc.d"
        echo "# Managed by mac-setup install.sh" > "$HOME/.zshrc.d/00-homebrew.zsh"
        echo "eval \"$shellenv_cmd\"" >> "$HOME/.zshrc.d/00-homebrew.zsh"
        eval "$shellenv_cmd"
    fi
}

brew_bundle_phase() {
    local label="$1"; local file="$2"
    [[ -f "$file" ]] || { info "$label Brewfile '$file' missing – skipped"; return 0; }
    log "Checking $label Brewfile ($file)"
    if brew bundle check --no-upgrade --file="$file" >/dev/null 2>&1; then
        info "$label dependencies already satisfied"
        return 0
    fi
    log "Installing $label packages from $file"
    if (( DRY_RUN )); then
        echo "DRY-RUN: brew bundle install --file=$file"
    else
        run brew bundle install --file="$file"
    fi
}

ensure_github_auth() {
    command -v gh >/dev/null 2>&1 || { warn "gh not installed yet (unexpected before internal phase)"; return 1; }
    if gh auth status >/dev/null 2>&1; then
        info "GitHub CLI already authenticated"
    else
        if [[ -t 0 && -t 1 ]]; then
            warn "GitHub CLI not authenticated. Launching 'gh auth login'..."
            if (( DRY_RUN )); then
                echo "DRY-RUN: gh auth login --scopes read:packages,repo"
            else
                gh auth login --scopes read:packages,repo || { warn "GitHub authentication failed/aborted"; return 1; }
            fi
        else
            warn "Non-interactive shell and gh not authenticated – skipping internal bundle"
            return 1
        fi
    fi
    if token=$(gh auth token 2>/dev/null); then
        export HOMEBREW_GITHUB_API_TOKEN="$token"
    fi
    return 0
}

run_brew_phases() {
    (( DO_BUNDLE )) || { info "Skipping all Brewfile bundle phases (--no-bundle)"; return 0; }
    # Phase 1
    if [[ -f Brewfile.bootstrap ]]; then
        brew_bundle_phase "bootstrap" "Brewfile.bootstrap"
    else
        warn "Brewfile.bootstrap missing – bootstrap phase skipped"
    fi
    # Phase 2
    if (( DO_INTERNAL_BUNDLE )); then
        if ensure_github_auth; then
            if [[ -f Brewfile.full ]]; then
                brew_bundle_phase "internal/full" "Brewfile.full"
            elif [[ -f Brewfile ]]; then
                brew_bundle_phase "internal/full" "Brewfile"
            else
                warn "No Brewfile.full or Brewfile found for internal phase"
            fi
        else
            warn "Skipping internal/full Brewfile phase (auth not established)"
        fi
    else
        info "Internal/full Brewfile phase skipped (flag)"
    fi
}

configure_gnu_tools() {
    (( DO_GNU )) || { info "Skipping GNU tools precedence (flag)"; return 0; }
    log "Configuring GNU tool precedence"
    ensure_dir "$HOME/.zshrc.d"
    local target="$HOME/.zshrc.d/10-gnu-tools.zsh"
    cat > "$target.tmp" <<'EOF'
# Managed by mac-setup (10-gnu-tools.zsh)
# Gives Homebrew GNU utilities precedence over macOS BSD variants.
_gnu_paths=(
    /opt/homebrew/opt/coreutils/libexec/gnubin
    /opt/homebrew/opt/findutils/libexec/gnubin
    /opt/homebrew/opt/gnu-sed/libexec/gnubin
    /opt/homebrew/opt/gnu-tar/libexec/gnubin
    /opt/homebrew/opt/grep/libexec/gnubin
    /opt/homebrew/opt/gawk/libexec/gnubin
    /opt/homebrew/opt/gnu-getopt/bin
)
for _p in "${_gnu_paths[@]}"; do
    [[ -d "$_p" ]] || continue
    case ":$PATH:" in
        *:"$_p":*) ;; # already
        *) PATH="$_p:$PATH" ;;
    esac
done
unset _p _gnu_paths

_gnu_manpaths=(
    /opt/homebrew/opt/coreutils/libexec/gnuman
    /opt/homebrew/opt/findutils/libexec/gnuman
    /opt/homebrew/opt/gnu-sed/libexec/gnuman
    /opt/homebrew/opt/gnu-tar/libexec/gnuman
    /opt/homebrew/opt/grep/libexec/gnuman
)
for _mp in "${_gnu_manpaths[@]}"; do
    [[ -d "$_mp" ]] || continue
    case ":${MANPATH:-}:" in
        *:"$_mp":*) ;;
        *) MANPATH="$_mp:${MANPATH:-}" ;;
    esac
done
unset _mp _gnu_manpaths
export PATH MANPATH
EOF
    if (( DRY_RUN )); then
        echo "DRY-RUN: write $target"; rm -f "$target.tmp"
    else
        mv "$target.tmp" "$target"
    fi
}

ensure_zshrc_sourcing() {
    local marker="# mac-setup .zshrc.d sourcing"
    local block=$'\n'"$marker"$'\nfor file in "$HOME"/.zshrc.d/*.zsh; do\n  [ -r "$file" ] && source "$file"\ndone\n'
    if [[ -f "$HOME/.zshrc" ]]; then
        grep -Fq "$marker" "$HOME/.zshrc" || { (( DRY_RUN )) && echo "DRY-RUN: append sourcing block to .zshrc" || echo "$block" >> "$HOME/.zshrc"; }
    else
        (( DRY_RUN )) && echo "DRY-RUN: create .zshrc with sourcing block" || echo "$block" > "$HOME/.zshrc"
    fi
}

install_oh_my_zsh() {
    (( DO_OHMYZSH )) || { info "Skipping Oh My Zsh (flag)"; return 0; }
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        info "Oh My Zsh already installed"
        return 0
    fi
    log "Installing Oh My Zsh (unattended)"
    run sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}

install_mise() {
    (( DO_MISE )) || { info "Skipping mise (flag)"; return 0; }
    ensure_dir "$HOME/.zshrc.d"
    local mise_file="$HOME/.zshrc.d/20-mise.zsh"
    # We now rely on Homebrew formula 'mise' instead of curl script.
    if command -v mise >/dev/null 2>&1; then
        info "Detected mise: $(mise --version 2>/dev/null | head -n1)"
    else
        warn "mise not found (brew phase may have skipped or internal phase not run). Run: brew bundle --file Brewfile.full (or install mise)"
    fi
    if (( DRY_RUN )); then
        echo "DRY-RUN: write $mise_file activation fragment"
    else
        cat > "$mise_file" <<'EOF'
# Managed by mac-setup (mise activation)
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
fi
EOF
    fi
    if (( DO_MISE_INSTALL )); then
        if command -v mise >/dev/null 2>&1; then
            log "Ensuring mise tools (mise install)"
            (( DRY_RUN )) && echo "DRY-RUN: mise install" || mise install || warn "mise install returned non-zero"
        else
            warn "Skipping 'mise install' because mise binary not present"
        fi
    else
        info "Skipping mise install step (flag)"
    fi
}

provision_dotfiles() {
    [[ -d dotfiles ]] || { info "No dotfiles/ directory present"; return 0; }
    local applied=0 skipped=0 backed_up=0
    for src in dotfiles/* dotfiles/.*; do
        # Skip if glob didn't match
        [[ -e "$src" ]] || continue
        # Skip . and ..
        local base
        base="${src##*/}"
        [[ "$base" == "." || "$base" == ".." ]] && continue
        # Skip common non-config artifacts
        [[ "$base" == "README"* || "$base" == *.md || "$base" == *.txt ]] && continue
        # Skip directories starting with .git (like .gitignore templates) only if you want? keep .gitignore though
        # If it's .gitconfig and git config disabled, skip
        if [[ "$base" == ".gitconfig" && $DO_GIT_CONFIG -eq 0 ]]; then
            skipped=$((skipped+1)); continue
        fi
        local target_base="$base"
        if [[ "$base" != .* ]]; then
            target_base=".$base"
        fi
        local target="$HOME/$target_base"
        # Determine action
        if [[ -f "$src" ]]; then
            if [[ -f "$target" ]] && cmp -s "$src" "$target"; then
                skipped=$((skipped+1)); continue
            fi
            if [[ -e "$target" && ! -e "${target}.backup.mac-setup" ]]; then
                (( DRY_RUN )) && echo "DRY-RUN: backup $target -> ${target}.backup.mac-setup" || cp -R "$target" "${target}.backup.mac-setup" && backed_up=$((backed_up+1)) || true
            fi
            (( DRY_RUN )) && echo "DRY-RUN: install $src -> $target" || cp "$src" "$target" && applied=$((applied+1))
        elif [[ -d "$src" ]]; then
            # For directories, sync (shallow copy) if new or different (naively always copy for simplicity)
            if [[ -d "$target" && ! -e "${target}.backup.mac-setup" ]]; then
                (( DRY_RUN )) && echo "DRY-RUN: backup dir $target -> ${target}.backup.mac-setup" || cp -R "$target" "${target}.backup.mac-setup" && backed_up=$((backed_up+1)) || true
            fi
            (( DRY_RUN )) && echo "DRY-RUN: copy dir $src -> $target" || { rm -rf "$target" 2>/dev/null || true; cp -R "$src" "$target" && applied=$((applied+1)); }
        else
            skipped=$((skipped+1))
            continue
        fi
    done
    info "Dotfiles provisioning: applied=$applied backed_up=$backed_up skipped=$skipped"
}

apply_macos_defaults() {
    (( DO_DEFAULTS )) || { info "Skipping macOS defaults (flag)"; return 0; }
    [[ -f macos-defaults.sh ]] || { warn "macos-defaults.sh not present"; return 0; }
    log "Applying macOS system preference defaults"
    if (( DRY_RUN )); then
        DRY_RUN=1 bash macos-defaults.sh || true
    else
        DRY_RUN=0 bash macos-defaults.sh
    fi
}

configure_aws_saml() {
    (( DO_AWS_SAML )) || { info "Skipping AWS SAML (flag)"; return 0; }
    local repo_url="https://github.com/LEGO/dope-user-support"
    local clone_dir="$HOME/.mac-setup/dope-user-support"
    local doc_url="https://github.com/LEGO/dope-user-support/blob/main/docs/saml2aws.md"
    # Ensure prerequisites
    if ! command -v git >/dev/null 2>&1; then
        warn "git not available – cannot configure AWS SAML now"; return 0; fi
    if ! command -v pwsh >/dev/null 2>&1; then
        warn "PowerShell (pwsh) not installed yet – skipping AWS SAML configuration. Re-run after 'brew bundle --file Brewfile.full' installs powershell."; return 0; fi
    # Clone or update
    if [[ -d "$clone_dir/.git" ]]; then
        ( cd "$clone_dir" && if (( DRY_RUN )); then echo "DRY-RUN: git pull --ff-only"; else git remote get-url origin >/dev/null 2>&1 && git pull --ff-only || true; fi )
    else
        ensure_dir "$(dirname "$clone_dir")"
        if (( DRY_RUN )); then
            echo "DRY-RUN: git clone $repo_url $clone_dir"
        else
            git clone "$repo_url" "$clone_dir" || { warn "Clone of $repo_url failed"; return 0; }
        fi
    fi
    # Run scripts
    local script1="$clone_dir/saml/create-cache.ps1"
    local script2="$clone_dir/saml/configure-saml2aws.ps1"
    if [[ ! -f "$script1" || ! -f "$script2" ]]; then
        warn "Expected SAML scripts not found in $clone_dir/saml – repository layout may have changed. See $doc_url"
        return 0
    fi
    if (( DRY_RUN )); then
        echo "DRY-RUN: pwsh -NoLogo -NoProfile -File $script1"
        echo "DRY-RUN: pwsh -NoLogo -NoProfile -File $script2"
    else
        log "Configuring AWS SAML (saml2aws) helper via dope-user-support repo"
        pwsh -NoLogo -NoProfile -File "$script1" || warn "create-cache.ps1 failed"
        pwsh -NoLogo -NoProfile -File "$script2" || warn "configure-saml2aws.ps1 failed"
        info "AWS SAML helper configuration attempted. For usage docs see: $doc_url"
    fi
}

configure_git() {
    (( DO_GIT_CONFIG )) || { info "Skipping git config (flag)"; return 0; }
    command -v git >/dev/null 2>&1 || { warn "git not installed yet – skipping git configuration"; return 0; }
    local existing_name existing_email
    existing_name=$(git config --global user.name || true)
    existing_email=$(git config --global user.email || true)
    if [[ -z "$existing_name" || -z "$existing_email" ]]; then
        local name email
        name=${GIT_USER_NAME:-}
        email=${GIT_USER_EMAIL:-}
        if [[ -n "$name" && -n "$email" ]]; then
            if (( DRY_RUN )); then
                echo "DRY-RUN: git config --global user.name '$name'"
                echo "DRY-RUN: git config --global user.email '$email'"
            else
                run git config --global user.name "$name"
                run git config --global user.email "$email"
                info "Configured git user.name/user.email ($name / $email)"
            fi
        else
            if (( DRY_RUN )); then
                echo "DRY-RUN: would prompt for git user.name / user.email (interactive)"
            else
                if [[ -t 0 && -t 1 ]]; then
                    info "Git identity not set. Interactive prompts below (leave blank to skip)."
                    if [[ -z "$existing_name" ]]; then
                        printf "Enter git user.name: " >&2
                        IFS= read -r name || true
                    fi
                    if [[ -z "$existing_email" ]]; then
                        printf "Enter git user.email: " >&2
                        IFS= read -r email || true
                    fi
                    if [[ -n "$name" && -n "$email" ]]; then
                        run git config --global user.name "$name"
                        run git config --global user.email "$email"
                        info "Configured git user.name/user.email ($name / $email)"
                    else
                        warn "Git user.name/email still unset (provide env vars or rerun to configure)."
                    fi
                else
                    warn "Git user.name/email not set and no interactive TTY. Export GIT_USER_NAME / GIT_USER_EMAIL and re-run to configure automatically."
                fi
            fi
        fi
    else
        info "Git user identity already set ($existing_name / $existing_email)"
    fi

    # Configure SSH commit signing (gpg.format=ssh)
    local current_format current_signingkey
    current_format=$(git config --global gpg.format || true)
    current_signingkey=$(git config --global user.signingkey || true)
    if [[ "$current_format" == "ssh" && -n "$current_signingkey" ]]; then
        info "Git SSH commit signing already configured (key: $current_signingkey)"
        return 0
    fi
    # Determine SSH public key to use
    local chosen_key=""
    if [[ -n "${GIT_SSH_SIGNING_KEY:-}" ]]; then
        if [[ -f "$GIT_SSH_SIGNING_KEY" ]]; then
            chosen_key="$GIT_SSH_SIGNING_KEY"
        else
            warn "GIT_SSH_SIGNING_KEY path not found: $GIT_SSH_SIGNING_KEY"
        fi
    fi
    if [[ -z "$chosen_key" ]]; then
        for cand in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ecdsa.pub" "$HOME/.ssh/id_rsa.pub"; do
            [[ -f "$cand" ]] || continue
            chosen_key="$cand"; break
        done
    fi
    if [[ -z "$chosen_key" ]]; then
        warn "No SSH public key found for commit signing (looked for id_ed25519.pub, id_ecdsa.pub, id_rsa.pub). Generate one (ssh-keygen -t ed25519) and re-run or set GIT_SSH_SIGNING_KEY."
        return 0
    fi
    if (( DRY_RUN )); then
        echo "DRY-RUN: git config --global gpg.format ssh"
        echo "DRY-RUN: git config --global user.signingkey $chosen_key"
        echo "DRY-RUN: git config --global commit.gpgsign true"
    else
        run git config --global gpg.format ssh
        run git config --global user.signingkey "$chosen_key"
        run git config --global commit.gpgsign true
        info "Enabled SSH commit signing with key: $chosen_key"
    fi
}

summary() {
    local end_epoch=$(date +%s)
    local dur=$(( end_epoch - START_TIME_EPOCH ))
    echo -e "\n${GREEN}Setup complete in ${dur}s${NC}"
    if (( DRY_RUN )); then
        echo "(dry run: no actual changes were made)"
    else
        echo "Restart your terminal or: source ~/.zshrc"
        if command -v code >/dev/null 2>&1; then
            local sentinel="$HOME/.local/state/mac-setup/vscode-extensions.done"
            if [[ ! -f "$sentinel" ]]; then
                echo "(VS Code) Launch VS Code once, then run:"
                echo "  ~/.mac-setup/scripts/install-vscode-extensions.sh"
            fi
        fi
        if (( DO_MISE )) && ! command -v mise >/dev/null 2>&1; then
            echo "(mise) Not installed yet. After installing via Brewfile.full: brew bundle --file Brewfile.full (or brew install mise)"
        fi
    fi
}

install_xcode_clt
install_homebrew
run_brew_phases
configure_gnu_tools
ensure_zshrc_sourcing
install_oh_my_zsh
install_mise
(( DO_DOTFILES )) && provision_dotfiles || info "Skipping dotfiles (flag)"
configure_git
apply_macos_defaults
configure_aws_saml
summary