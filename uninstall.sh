#!/bin/bash
# uninstall.sh — removes the launchd agent. Desktop files and folders are left untouched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
rm -f "$PLIST"

echo "Agent $LAUNCHD_LABEL removed."
