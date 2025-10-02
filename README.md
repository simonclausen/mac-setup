# mac-setup

Minimal, repeatable macOS, and very opinionated, dev environment bootstrap with two-phase Homebrew install and safe re-runs.

## Quick start

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/simonclausen/mac-setup/main/bootstrap.sh)"
```

## What it does

- Installs / updates Homebrew (idempotent)
- Two-phase package install (public first, internal after `gh auth login`)
- Creates modular `~/.zshrc.d` fragments (Homebrew, GNU tools, mise)
- Optional: macOS defaults, Oh My Zsh, mise tools, git config, AWS SAML helper
- Optional: macOS defaults, Oh My Zsh, mise tools, git config (with SSH commit signing), AWS SAML helper
- Copies any files in `dotfiles/` into `$HOME` (prefixing with a dot when needed) with single backup per file
- Safe re-run: avoids duplicate lines, backs up existing `~/.gitconfig` once
- `--dry-run` preview mode

## Two-phase packages

Phase 1: `Brewfile.bootstrap` (public prereqs: git, gh, jq, etc.)  
Phase 2: `Brewfile.full` (full + internal/private taps). Skipped if not authenticated.

Authenticate & continue later:

```bash
gh auth login
brew bundle --file Brewfile.full
```

`Brewfile` at repo root is a stub to prevent accidental single-phase use.

### VS Code extensions

Extensions install after first manual launch (Gatekeeper approval). Then run:

```bash
~/.mac-setup/scripts/install-vscode-extensions.sh
```

Add `--dry-run` to preview. A sentinel file prevents duplicates.

## Common flags

```text
--dry-run             Preview actions only
--no-brew-update      Skip brew update
--no-bundle           Skip all Brewfile phases
--no-internal-bundle  Skip phase 2
--no-gnu              Skip GNU precedence config
--no-defaults         Skip macOS defaults
--no-ohmyzsh          Skip Oh My Zsh
--no-mise             Skip mise (and tools)
--no-mise-install     Activate mise only
--no-git-config       Skip git config
--no-dotfiles         Skip generic dotfiles provisioning
--no-aws-saml         Skip AWS SAML role helper configuration
--verbose             Shell trace
```

Examples:

```bash
~/.mac-setup/install.sh --dry-run
~/.mac-setup/install.sh --no-internal-bundle
```

## macOS defaults (preview)

```bash
DRY_RUN=1 bash macos-defaults.sh
```

## Uninstall (lightweight)

```bash
rm -f ~/.zshrc.d/00-homebrew.zsh ~/.zshrc.d/10-gnu-tools.zsh ~/.zshrc.d/20-mise.zsh
mv ~/.gitconfig.backup.mac-setup ~/.gitconfig 2>/dev/null || true
```

## Troubleshooting

- PATH issues: open new shell or `source ~/.zshrc`
- Check pending packages: `brew bundle check --file Brewfile.full`
- Internal phase skipped? Run `gh auth login` then re-run full bundle.

## AWS SAML (saml2aws) helper

If PowerShell (`pwsh`) is installed (via `Brewfile.full`), the installer will attempt to clone `LEGO/dope-user-support` into `~/.mac-setup/dope-user-support` and run:

```bash
saml/create-cache.ps1
saml/configure-saml2aws.ps1
```

Skip with `--no-aws-saml`.

Further usage & role switching docs:

[SAML2AWS usage docs](https://github.com/LEGO/dope-user-support/blob/main/docs/saml2aws.md)

## Git configuration & SSH commit signing

If `user.name` / `user.email` aren't already set globally and environment variables are provided, they will be applied:

```bash
export GIT_USER_NAME="Jane Developer"
export GIT_USER_EMAIL="jane.developer@example.com"
```

SSH-based commit signing is enabled automatically when possible:

1. Determines a signing key (in order): `$GIT_SSH_SIGNING_KEY`, `~/.ssh/id_ed25519.pub`, `~/.ssh/id_ecdsa.pub`, `~/.ssh/id_rsa.pub`.
2. Sets:
   - `gpg.format=ssh`
   - `user.signingkey=<path-to-public-key>`
   - `commit.gpgsign=true`

If no suitable key is found you will see a warning; generate one, e.g.:

```bash
ssh-keygen -t ed25519 -C "jane.developer@example.com"
```

Then re-run the installer (or manually configure git).
