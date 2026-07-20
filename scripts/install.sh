#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
label="com.gloria.finally-good-blocker-app"
binary_name="FinallyGoodBlockerApp"
user_apps_dir="$HOME/Applications"
installed_app="$user_apps_dir/finally-good-blocker-app.app"
agent_dir="$HOME/Library/LaunchAgents"
agent_path="$agent_dir/$label.plist"
agent_template="$project_dir/Resources/$label.plist"
built_app="$project_dir/build/finally-good-blocker-app.app"
service_target="gui/$UID/$label"

zsh "$script_dir/package-app.sh" release

mkdir -p "$user_apps_dir" "$agent_dir"
launchctl bootout "$service_target" 2>/dev/null || true
pkill -x "$binary_name" 2>/dev/null || true

if [[ -e "$installed_app" ]]; then
    if [[ "$installed_app" != "$HOME/Applications/finally-good-blocker-app.app" ]]; then
        echo "Refusing to replace unexpected app path: $installed_app" >&2
        exit 1
    fi
    rm -rf -- "$installed_app"
fi

ditto "$built_app" "$installed_app"
cp "$agent_template" "$agent_path"
plutil -replace ProgramArguments -json \
    "[\"$installed_app/Contents/MacOS/$binary_name\"]" \
    "$agent_path"
plutil -lint "$agent_path" >/dev/null

launchctl bootstrap "gui/$UID" "$agent_path"
launchctl enable "$service_target"
launchctl kickstart -k "$service_target"

echo "Installed persistent blocker at $installed_app"
echo "It will launch at login and relaunch if it exits."
echo "Run zsh $project_dir/scripts/uninstall.sh to remove it."
