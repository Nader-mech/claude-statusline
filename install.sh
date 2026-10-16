#!/bin/bash
# Installs the status line into ~/.claude and points Claude Code's settings.json at it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
dir="$HOME/.claude"
settings="$dir/settings.json"

command -v jq >/dev/null || { echo "jq is required. Install it first (brew/apt/dnf/winget install jq)." >&2; exit 1; }

mkdir -p "$dir"
cp "$here/statusline-usage.sh" "$dir/statusline-usage.sh"
chmod +x "$dir/statusline-usage.sh"

[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak"
# refreshInterval redraws every 10 s so the countdown stays current while idle (Claude Code 2.1.97+).
jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline-usage.sh", "refreshInterval": 10}' "$settings.bak" > "$settings"

echo "Installed. Old settings saved to $settings.bak"
echo "Start a new Claude Code session to see the status line."
