#!/bin/zsh

set -euo pipefail

label="com.gloria.finally-good-blocker-app"
binary_name="FinallyGoodBlockerApp"
installed_app="$HOME/Applications/finally-good-blocker-app.app"
agent_path="$HOME/Library/LaunchAgents/$label.plist"
service_target="gui/$UID/$label"

launchctl bootout "$service_target" 2>/dev/null || true
pkill -x "$binary_name" 2>/dev/null || true
rm -f -- "$agent_path"

if [[ "$installed_app" != "$HOME/Applications/finally-good-blocker-app.app" ]]; then
    echo "Refusing to remove unexpected app path: $installed_app" >&2
    exit 1
fi
rm -rf -- "$installed_app"

echo "Removed the persistent blocker and its login agent."
