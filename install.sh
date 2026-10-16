#!/bin/bash
# Installs the status line into ~/.claude and points Claude Code's settings.json at it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
dir="$HOME/.claude"
settings="$dir/settings.json"

command -v jq >/dev/null || { echo "jq is required. Install it first (brew/apt/dnf/winget install jq)." >&2; exit 1; }

mkdir -p "$dir"
# Check the existing settings before touching anything: exactly one JSON object, or nothing at all
# (a missing, empty or whitespace-only file counts as {}).
src=/dev/null
if [ -e "$settings" ]; then
  docs=$(jq -s 'if all(type == "object") then length else -1 end' "$settings" 2>/dev/null) || docs=-1
  case $docs in
    0) ;;
    1) src=$settings ;;
    *) echo "$settings isn't a single valid JSON object (a trailing comma or a comment?), so it was left alone." >&2
       echo "Fix it and run this again." >&2
       exit 1 ;;
  esac
fi

cp "$here/statusline-usage.sh" "$dir/statusline-usage.sh"
chmod +x "$dir/statusline-usage.sh"

# Write the new settings to a temp file and only replace the original once that worked.
# Each run keeps its own timestamped backup, so a second run never overwrites the first.
tmp=$(mktemp "$settings.XXXXXX")
trap 'rm -f "$tmp"' EXIT
backup=""
if [ -s "$settings" ]; then
  backup="$settings.bak.$(date +%Y%m%d-%H%M%S)" n=1
  while [ -e "$backup" ]; do backup="$settings.bak.$(date +%Y%m%d-%H%M%S).$n"; n=$((n + 1)); done
fi
# refreshInterval redraws every 10 s so the countdown stays current while idle (Claude Code 2.1.97+).
jq -n --slurpfile old "$src" '($old[0] // {}) + {statusLine: {"type": "command", "command": "bash ~/.claude/statusline-usage.sh", "refreshInterval": 10}}' > "$tmp"
jq -e '.statusLine.command' "$tmp" >/dev/null
[ -n "$backup" ] && cp -p "$settings" "$backup" # cp follows a symlink, so this backs up the real file
if [ -L "$settings" ]; then
  # A symlinked settings.json (stow, chezmoi, home-manager...): write through the link, which keeps
  # the link, the real file and its permissions.
  cat "$tmp" > "$settings"
else
  [ -f "$settings" ] && chmod "$(stat -L -c %a "$settings" 2>/dev/null || stat -L -f %Lp "$settings")" "$tmp" # keep its permissions
  mv "$tmp" "$settings"
fi

echo "Installed.${backup:+ Old settings saved to $backup}"
echo "Start a new Claude Code session to see the status line."
