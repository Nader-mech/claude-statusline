# claude-statusline

A two-line Claude Code status line: your context window on top, your subscription limits underneath.

```
◆ Opus 5.5   context ███░░░░░░░░░░░░░░░░░ 15%   154k used · 846k free
⏱ 5h ███▌░░░░░░ 35% ↻ 2h 30m  │  week ████▊░░░░░ 48% ↻ 2d 21h 27m
```

When your pace would hit a limit before it resets, that window turns red and says when:

```
⏱ 5h ███████▋░░ 76% ↻ 3h 10m  ⚠ runs out in 35m  │  week ██████░░░░ 60% ↻ 3d 11h 20m
```

## What it shows

- **Context**: how full this conversation's context window is, with tokens used and free
- **5-hour and weekly limits**: a bar, the percent used, and a countdown to the reset (`↻ 1d 2h 3m`)
- **Run-out warning**: compares how much you've used with how much of the window has passed. If you'd hit 100% before the reset, it shows `⚠ runs out in …`. It stays quiet for the first 5% of a window, where the pace is mostly noise.
- **Colours**: green under 50%, yellow under 80%, red from 80%. Bars fill in 1/8-cell steps on a dim track, so 1% is a sliver and 0% is clearly empty.
- **Fits your terminal**: each line steps down through four layouts (wide, compact, tight, minimal) until it fits the width. Nothing overflows from 54 columns up.
- **Instant at session start**: the last known limits are cached, so they show before your first reply, marked with `~` (e.g. `~week 60%`). A cached window disappears once its reset time passes.

Usage limits come from the `rate_limits` field Claude Code passes to status line scripts, which is only there on Pro and Max plans. With an API key you get line 1 only.

One bash file, one dependency (`jq`), about 10 ms per refresh. Every value from Claude Code or the cache is checked to be a plain number before use.

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
"statusLine": { "type": "command", "command": "bash ~/.claude/statusline-usage.sh", "refreshInterval": 10 }
```

`refreshInterval` redraws the line every 10 seconds so the countdown keeps moving while you're idle. It needs Claude Code 2.1.97 or later; on older versions, drop it and the line updates after each reply.

Start a new Claude Code session to see it.

## Platforms

| Platform | Status |
|---|---|
| macOS (bash 3.2, `sh`) | tested |
| bash 5.3 with GNU coreutils (as on Linux) | tested |
| WSL | same as Linux |
| Windows, Git Bash | expected to work, not tested on a real machine |

## Uninstall

Delete the `statusLine` block from `~/.claude/settings.json`, then remove `~/.claude/statusline-usage.sh` and `~/.claude/cache/statusline-usage.cache`.

## License

MIT
