#!/bin/bash
# Installs the status line into ~/.claude and points Claude Code's settings.json at it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
dir="$HOME/.claude"
settings="$dir/settings.json"

command -v jq >/dev/null || { echo "jq is required. Install it first (brew/apt/dnf/winget install jq)." >&2; exit 1; }

mkdir -p "$dir"
# Check the existing settings before touching anything. An empty file counts as {}.
if [ -s "$settings" ] && ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
  echo "$settings isn't a valid JSON object (a trailing comma or a comment?), so it was left alone." >&2
  echo "Fix it and run this again." >&2
  exit 1
fi

cp "$here/statusline-usage.sh" "$dir/statusline-usage.sh"
chmod +x "$dir/statusline-usage.sh"

# Write the new settings to a temp file and only replace the original once that worked.
# Each run keeps its own timestamped backup, so a second run never overwrites the first.
tmp=$(mktemp "$settings.XXXXXX")
trap 'rm -f "$tmp"' EXIT
backup=""
if [ -s "$settings" ]; then
  src=$settings
  backup="$settings.bak.$(date +%Y%m%d-%H%M%S)" n=1
  while [ -e "$backup" ]; do backup="$settings.bak.$(date +%Y%m%d-%H%M%S).$n"; n=$((n + 1)); done
else
  src=/dev/null
fi
# refreshInterval redraws every 10 s so the countdown stays current while idle (Claude Code 2.1.97+).
jq -n --slurpfile old "$src" '($old[0] // {}) + {statusLine: {"type": "command", "command": "bash ~/.claude/statusline-usage.sh", "refreshInterval": 10}}' > "$tmp"
jq -e '.statusLine.command' "$tmp" >/dev/null
[ -n "$backup" ] && cp -p "$settings" "$backup"
[ -f "$settings" ] && chmod "$(stat -c %a "$settings" 2>/dev/null || stat -f %Lp "$settings")" "$tmp" # keep its permissions
mv "$tmp" "$settings"

echo "Installed.${backup:+ Old settings saved to $backup}"
echo "Start a new Claude Code session to see the status line."
