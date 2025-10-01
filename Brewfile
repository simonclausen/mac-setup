###############################################
# This project now uses a two-phase approach:
#   Phase 1 (public):   Brewfile.bootstrap
#   Phase 2 (internal): Brewfile.full
#
# Usage example:
#   brew bundle --file Brewfile.bootstrap
#   gh auth login   # authenticate with GitHub for private taps
#   brew bundle --file Brewfile.full
#
# This stub intentionally aborts to prevent accidental use of the
# legacy single-file model which could fail before authentication.
# Edit Brewfile.bootstrap or Brewfile.full instead.
###############################################

abort <<~MSG
	Use phased install for this project:

		brew bundle --file Brewfile.bootstrap
		gh auth login
		brew bundle --file Brewfile.full

	(Or run ./install.sh which orchestrates both phases.)

	Modify Brewfile.bootstrap (public prereqs) or Brewfile.full (full/internal)
	rather than this stub.
MSG