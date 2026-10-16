# claude-statusline

A Claude Code status line that shows how much of your subscription you've used, for the 5-hour window and the 7-day week.

```
5h ████░░░░░░ 42% resets 12:40  ·  week ████████░░ 81% resets Sat 11:40  · Opus 5.5
```

- Green under 50%, yellow under 80%, red from 80%
- Shows the time each window resets
- Remembers the last values, so the bars show as soon as a session starts (tagged `(last known)` until fresh data arrives). A cached window disappears once its reset time has passed.
- One bash file, one dependency (`jq`), about 10 ms per refresh

Usage data comes from the `rate_limits` field Claude Code passes to status line scripts, which is only there on Pro and Max plans. With an API key you'll see just the model name.

## Install

Install `jq` first:

| OS | Command |
|---|---|
| macOS | `brew install jq` |
| Debian / Ubuntu | `sudo apt install jq` |
| Fedora | `sudo dnf install jq` |
| Windows | `winget install jqlang.jq` |

Then:

```bash
git clone https://github.com/Nader-mech/claude-statusline.git
cd claude-statusline
./install.sh
```

`install.sh` copies the script to `~/.claude/` and adds this to `~/.claude/settings.json` (your old settings are saved to `settings.json.bak`):

```json
"statusLine": { "type": "command", "command": "bash ~/.claude/statusline-usage.sh" }
```

Start a new Claude Code session to see it.

## Platforms

| Platform | Status |
|---|---|
| macOS (bash 3.2, BSD date) | tested |
| Linux (bash 5, GNU date) | tested |
| WSL | same as Linux |
| Windows, Git Bash | expected to work, not tested on a real machine |

## Uninstall

Delete the `statusLine` block from `~/.claude/settings.json`, then remove `~/.claude/statusline-usage.sh` and `~/.claude/cache/statusline-usage.cache`.

## License

MIT
