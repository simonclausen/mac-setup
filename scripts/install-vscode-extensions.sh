#!/usr/bin/env bash
set -euo pipefail

# Install VS Code extensions after the user has launched VS Code once
# (Gatekeeper approval). Idempotent: installs only missing extensions and
# writes a sentinel file.

EXTENSIONS=(
  almenon.arepl
  bierner.markdown-mermaid
  charliermarsh.ruff
  davidanson.vscode-markdownlint
  dotjoshjohnson.xml
  eamodio.gitlens
  esbenp.prettier-vscode
  github.copilot
  github.copilot-chat
  github.vscode-github-actions
  github.vscode-pull-request-github
  gruntfuggly.todo-tree
  hashicorp.terraform
  kevinrose.vsc-python-indent
  ms-azuretools.vscode-containers
  ms-azuretools.vscode-docker
  ms-kubernetes-tools.vscode-kubernetes-tools
  ms-python.debugpy
  ms-python.isort
  ms-python.python
  ms-python.vscode-pylance
  ms-python.vscode-python-envs
  ms-vscode.test-adapter-converter
  njpwerner.autodocstring
  redhat.vscode-yaml
  samuelcolvin.jinjahtml
  streetsidesoftware.code-spell-checker
  takumii.markdowntable
  tonybaloney.vscode-pets
  trunk.io
)

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--dry-run]

Installs predefined VS Code extensions after first manual launch of VS Code.
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

SENTINEL_DIR="$HOME/.local/state/mac-setup"
SENTINEL_FILE="$SENTINEL_DIR/vscode-extensions.done"

if [[ -f "$SENTINEL_FILE" ]]; then
  echo "VS Code extensions already installed (sentinel present)"; exit 0
fi

if ! command -v code >/dev/null 2>&1; then
  echo "'code' CLI not found. Launch Visual Studio Code once (to complete Gatekeeper approval) and ensure the 'code' command is available (Shell Command: Install 'code')." >&2
  exit 1
fi

# Simple heuristic that VS Code has been launched at least once.
if [[ ! -d "$HOME/Library/Application Support/Code" ]]; then
  echo "VS Code user data directory not found yet. Launch VS Code once, then re-run this script." >&2
  exit 1
fi

installed_list=$(code --list-extensions 2>/dev/null || true)
missing=()
for ext in "${EXTENSIONS[@]}"; do
  if grep -Fxq "$ext" <<<"$installed_list"; then
    echo "Already installed: $ext"
  else
    missing+=("$ext")
  fi
done

if ((${#missing[@]}==0)); then
  echo "All extensions already present. Writing sentinel.";
  mkdir -p "$SENTINEL_DIR"
  date > "$SENTINEL_FILE"
  exit 0
fi

echo "Installing ${#missing[@]} missing extensions..."
for ext in "${missing[@]}"; do
  if (( DRY_RUN )); then
    echo "DRY-RUN: code --install-extension $ext"
  else
    if code --install-extension "$ext" >/dev/null; then
      echo "Installed: $ext"
    else
      echo "Failed: $ext" >&2
    fi
  fi
done

if (( ! DRY_RUN )); then
  mkdir -p "$SENTINEL_DIR"
  date > "$SENTINEL_FILE"
  echo "Done. Sentinel written: $SENTINEL_FILE"
else
  echo "Dry run complete. Sentinel not written."
fi