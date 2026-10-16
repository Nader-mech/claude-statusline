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

One script per platform: bash with `jq` on macOS and Linux (about 10 ms per refresh), PowerShell with nothing extra on Windows. Every value from Claude Code or the cache is checked to be a plain number before use.

## Install

### macOS and Linux

Install `jq` (`brew install jq`, `sudo apt install jq` or `sudo dnf install jq`), then:

```bash
git clone https://github.com/Nader-mech/claude-statusline.git
cd claude-statusline
./install.sh
```

### Windows

No `jq` needed. In PowerShell:

```powershell
git clone https://github.com/Nader-mech/claude-statusline.git
cd claude-statusline
powershell -ExecutionPolicy Bypass -File install.ps1
```

This installs `statusline-usage.ps1`, a PowerShell version of the same script. It prints identical output and works whether Claude Code runs commands through Git Bash or PowerShell. If you use Git Bash and have `jq`, `./install.sh` works on Windows too.

### What the installers do

They copy the script into `~/.claude/` and add a `statusLine` block to `~/.claude/settings.json`, keeping everything else and saving the old file as `settings.json.bak`. On macOS and Linux it looks like this:

```json
"statusLine": { "type": "command", "command": "bash ~/.claude/statusline-usage.sh", "refreshInterval": 10 }
```

`refreshInterval` redraws the line every 10 seconds so the countdown keeps moving while you're idle. It needs Claude Code 2.1.97 or later; on older versions, drop it and the line updates after each reply.

Start a new Claude Code session to see it.

## Platforms

| Platform | Script | Tested in CI |
|---|---|---|
| macOS | `statusline-usage.sh` (bash 3.2 and `sh`) | yes |
| Linux | `statusline-usage.sh` | yes |
| Windows, PowerShell 5.1 or 7 | `statusline-usage.ps1` | yes |
| Windows, Git Bash | `statusline-usage.sh` | yes |

Every push runs [`tests/parity.sh`](tests/parity.sh) on macOS, Linux and Windows. It feeds 58 cases (normal use, warnings, every width, cached values, broken input) to each version and fails if any output differs by a single byte.

## Uninstall

Delete the `statusLine` block from `~/.claude/settings.json`, then remove `~/.claude/statusline-usage.sh` (or `.ps1` on Windows) and `~/.claude/cache/statusline-usage.cache`.

## License

MIT
