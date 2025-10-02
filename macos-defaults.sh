#!/usr/bin/env bash

set -euo pipefail

# Idempotent macOS defaults application
# Supports DRY_RUN=1 environment variable for preview mode

DRY_RUN=${DRY_RUN:-0}

_run() {
    if (( DRY_RUN )); then
        # Print a shell-escaped version of the command to show exact tokens
        printf 'DRY-RUN: '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

if [[ "$DRY_RUN" == "1" ]]; then
    echo "Applying macOS system preferences... (dry-run)"
else
    echo "Applying macOS system preferences..."
fi

# Close System Preferences to prevent conflicts
osascript -e 'tell application "System Preferences" to quit'

# ==============================================
# General UI/UX
# ==============================================

apply_nvram() {
    local key=$1 value=$2
    if nvram -p 2>/dev/null | grep -q "^${key}\s*${value// / }$"; then
        echo "nvram ${key} already set"
    else
        _run sudo nvram "${key}=${value}"
    fi
}

# Disable the sound effects on boot
apply_nvram SystemAudioVolume " "

# Save to disk (not to iCloud) by default
_run defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

# Automatically quit printer app once the print jobs complete
_run defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

# Disable the "Are you sure you want to open this application?" dialog
#_run defaults write com.apple.LaunchServices LSQuarantine -bool false

# ==============================================
# Security & Privacy
# ==============================================

# Require password immediately after sleep or screen saver begins
_run defaults write com.apple.screensaver askForPassword -int 1
_run defaults write com.apple.screensaver askForPasswordDelay -int 0

# Enable firewall
_run sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Enable stealth mode
_run sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# ==============================================
# Keyboard & Input
# ==============================================

# Enable full keyboard access for all controls
_run defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# Set a fast keyboard repeat rate
_run defaults write NSGlobalDomain KeyRepeat -int 2
_run defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Disable smart quotes and dashes
_run defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
_run defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# ==============================================
# Finder
# ==============================================

# Show hidden files by default
_run defaults write com.apple.finder AppleShowAllFiles -bool true

# Show all filename extensions
_run defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show status bar
_run defaults write com.apple.finder ShowStatusBar -bool true

# Show path bar
_run defaults write com.apple.finder ShowPathbar -bool true

# Display full POSIX path as Finder window title
_run defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Keep folders on top when sorting by name
_run defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Use list view in all Finder windows by default
_run defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Disable the warning when changing a file extension
_run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# ==============================================
# Dock & Mission Control
# ==============================================

# Set the icon size of Dock items
_run defaults write com.apple.dock tilesize -int 48

# Enable dock auto-hide
_run defaults write com.apple.dock autohide -bool true

# Make Dock icons of hidden applications translucent
_run defaults write com.apple.dock showhidden -bool true

# Don't show recent applications in Dock
_run defaults write com.apple.dock show-recents -bool false

# Speed up Mission Control animations
_run defaults write com.apple.dock expose-animation-duration -float 0.

# Remove default icons from the Dock
_run defaults delete com.apple.dock persistent-apps

# ==============================================
# Terminal & Development
# ==============================================

# Only use UTF-8 in Terminal.app
_run defaults write com.apple.terminal StringEncodings -array 4

# Enable Secure Keyboard Entry in Terminal.app
_run defaults write com.apple.terminal SecureKeyboardEntry -bool true

# ==============================================
# Time Machine
# ==============================================

# Prevent Time Machine from prompting to use new hard drives as backup volume
_run defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# ==============================================
# Activity Monitor
# ==============================================

# Show the main window when launching Activity Monitor
_run defaults write com.apple.ActivityMonitor OpenMainWindow -bool true

# Visualize CPU usage in the Activity Monitor Dock icon
_run defaults write com.apple.ActivityMonitor IconType -int 5

# Show all processes in Activity Monitor
_run defaults write com.apple.ActivityMonitor ShowCategory -int 0

# ==============================================
# Software Updates
# ==============================================

# Enable the automatic update check
_run defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true

# Check for software updates daily, not just once per week
_run defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

# Download newly available updates in background
_run defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1

# ==============================================
# Kill affected applications
# ==============================================

echo "Restarting affected applications (excluding Terminal)..."
if (( ! DRY_RUN )); then
    for app in "Activity Monitor" \
            "Dock" \
            "Finder" \
            "SystemUIServer"; do
            killall "${app}" &> /dev/null || true
    done
    echo "NOTE: Restart Terminal manually to apply Terminal-specific settings (or open a new window/tab)."
else
    echo "DRY-RUN: would restart Activity Monitor, Dock, Finder, SystemUIServer"
    echo "DRY-RUN: (Terminal not auto-terminated; restart manually after applying for full effect)"
fi

if (( DRY_RUN )); then
    echo "macOS defaults (dry-run) complete. No changes applied."
else
    echo "macOS defaults applied! Some changes may require logout/restart."
fi