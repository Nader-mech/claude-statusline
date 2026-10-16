#!/bin/bash
# Status line, two lines: the model and context window use, then the 5-hour and 7-day
# subscription limits with reset countdowns, warning when the pace would run a limit out early.
# Runs on macOS, Linux, WSL and Git Bash. Needs jq.
input=$(cat)
cache="$HOME/.claude/cache/statusline-usage.cache"

num() { # $1 = variable name; leaves a plain integer in it, or "-" for anything else
  local v=${!1}
  case $v in ''|*[!0-9]*) v=- ;; *) [ ${#v} -le 12 ] && v=$((10#$v)) || v=- ;; esac
  printf -v "$1" %s "$v"
}
now=${EPOCHSECONDS:-}; num now; [ "$now" = - ] && now=$(date +%s)
cols=${COLUMNS:-}; num cols # terminal width, set by Claude Code; 0 or unset means unknown

# One jq call: numbers are rounded to integers, anything else becomes "-",
# and control characters are stripped from the model name.
five= five_at= week= week_at= ctx= ctx_used= ctx_size= five10= week10= model=
j=$(jq -r '
  def n(p): (try p catch null) | if type == "number" then ([., 0] | max | . + 0.5 | floor | tostring) else "-" end;
  def n10(p): (try p catch null) | if type == "number" then ([. * 10, 0] | max | floor | tostring) else "-" end;
  [ n(.rate_limits.five_hour.used_percentage), n(.rate_limits.five_hour.resets_at),
    n(.rate_limits.seven_day.used_percentage), n(.rate_limits.seven_day.resets_at),
    n(.context_window.used_percentage), n(.context_window.context_window_size),
    n(.context_window.current_usage | .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens),
    n10(.rate_limits.five_hour.used_percentage), n10(.rate_limits.seven_day.used_percentage),
    ((try .model.display_name catch null) // "" | tostring | gsub("[[:cntrl:]]"; "")) ] | join("\t")
' 2>/dev/null <<<"$input")
IFS=$'\t' read -r five five_at week week_at ctx ctx_size ctx_used five10 week10 model <<<"$j"
model=${model%$'\r'} # native Windows jq.exe ends lines with CRLF
for v in five five_at week week_at ctx ctx_size ctx_used five10 week10; do num $v; done
live=""; [ "$five$week" != "--" ] && live=1

# Cache the last known values so the bars show at session start, before the first reply.
# A live window wins; a cached one is used only while its reset time is still ahead.
c5= c5_at= cw= cw_at= cached="" five_c="" week_c=""
[ -f "$cache" ] && [ -r "$cache" ] && read -r c5 c5_at cw cw_at 2>/dev/null < "$cache"
for v in c5 c5_at cw cw_at; do num $v; done
if [ "$five" = - ] && [ "$c5" != - ] && [ "$c5_at" != - ] && [ "$c5_at" -gt "$now" ]; then five=$c5 five_at=$c5_at five10=- five_c=1 cached=1; fi
if [ "$week" = - ] && [ "$cw" != - ] && [ "$cw_at" != - ] && [ "$cw_at" -gt "$now" ]; then week=$cw week_at=$cw_at week10=- week_c=1 cached=1; fi

new="$five $five_at $week $week_at"
if [ -n "$live" ] && [ ! -d "$cache" ] && [ "$new" != "$c5 $c5_at $cw $cw_at" ]; then
  tmp="$cache.$$" # per-process temp file, so parallel sessions never collide
  trap 'rm -f "$tmp" 2>/dev/null; exit 1' INT TERM HUP # Claude Code cancels a run when a newer one starts
  { [ -d "${cache%/*}" ] || mkdir -p "${cache%/*}"
    rm -f "$cache".[0-9]* # temp files left by runs that were killed outright
    printf '%s\n' "$new" > "$tmp" && mv -f "$tmp" "$cache"; } 2>/dev/null \
    || rm -f "$tmp" 2>/dev/null
  trap - INT TERM HUP
fi

tokens() { # $1 = token count; sets $t to e.g. "850", "145k", "1.2M" or "1M"
  local tenths=$(( ($1 + 50000) / 100000 ))
  if [ $1 -lt 1000 ]; then t=$1
  elif [ $1 -lt 999500 ]; then t="$(( ($1 + 500) / 1000 ))k"
  elif [ $(( tenths % 10 )) -eq 0 ]; then t="$(( tenths / 10 ))M"
  else t="$(( tenths / 10 )).$(( tenths % 10 ))M"; fi
}
colours() { # $1 = on, or off to measure a line's width
  if [ "$1" = on ]; then dim=$'\033[2m' bold=$'\033[1m' green=$'\033[32m' yellow=$'\033[33m' red=$'\033[31m' reset=$'\033[0m'
  else dim="" bold="" green="" yellow="" red="" reset=""; fi
}
paint() { # $1 = percent; sets $c: green under 50, yellow under 80, red above
  c=$green; [ $1 -ge 50 ] && c=$yellow; [ $1 -ge 80 ] && c=$red
}
dur() { # $1 = seconds; sets $when to e.g. "1d 2h 3m", zero units dropped, minutes rounded up (no minutes past a day when narrow)
  local m d h; when=""
  m=$(( ($1 + 59) / 60 )); d=$(( m / 1440 )); h=$(( m % 1440 / 60 )); m=$(( m % 60 ))
  [ $d -gt 0 ] && when="${d}d"
  [ $h -gt 0 ] && when+="${when:+ }${h}h"
  [ $m -gt 0 ] && { [ -z "$narrow" ] || [ $d -eq 0 ]; } && when+="${when:+ }${m}m"
  [ -n "$when" ] || when="0m"
}
eighths=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
bar() { # $1 = percent, $2 = width in cells; sets $b: smooth fill in $c (1/8-cell steps) on a dim track
  local p=$1 e full i on="" off=""
  [ $p -gt 100 ] && p=100
  e=$(( (p * $2 * 8 + 50) / 100 )); full=$(( e / 8 ))
  for ((i = 0; i < full; i++)); do on+="█"; done
  [ $(( e % 8 )) -gt 0 ] && on+="${eighths[e % 8]}" && full=$(( full + 1 ))
  for ((i = full; i < $2; i++)); do off+="░"; done
  b="${c}${on}${reset}${dim}${off}${reset}"
}
limit() { # $1 = label, $2 = percent, $3 = resets_at, $4 = window length in seconds, $5 = percent in tenths,
         # $6 = set when the values came from the cache; appends to $line
  [ "$2" = - ] && return
  local p=$2 p10=$5 left elapsed out seg=""
  [ "$p10" = - ] && p10=$(( p * 10 )) # cached values carry no tenths
  [ -n "$6" ] && seg="${dim}~${reset}" # marks this window as last known
  paint $p; seg+="$1 "
  [ $lbar -gt 0 ] && bar $p $lbar && seg+="${b} "
  seg+="${c}${p}%${reset}"
  if [ "$3" != - ] && [ "$3" -gt "$now" ]; then
    left=$(( $3 - now )); elapsed=$(( $4 - left ))
    dur $left; seg+=" ${dim}↻ ${when}${reset}"
    # Warn only when the pace so far (used × window ÷ elapsed, in tenths of a percent so rounding
    # can't trigger it) runs out more than a minute before the reset. Skipped in the first 5% of
    # the window, where the pace is mostly noise.
    if [ $p10 -ge 1000 ]; then seg+="${wgap}${red}⚠${full_msg}${reset}"
    elif [ $p10 -gt 0 ] && [ $elapsed -ge $(( $4 / 20 )) ]; then
      out=$(( (1000 - p10) * elapsed / p10 ))
      [ $out -lt $(( left - 60 )) ] && dur $(( out > 0 ? out : 1 )) && seg+="${wgap}${red}⚠ ${out_msg} ${when}${reset}"
    fi
  fi
  line+="${line:+$sep}$seg"
}
vis() { # $1 = line without colour codes; sets $w to its width (UTF-8 continuation bytes don't count)
  local LC_ALL=C s
  s=${1//[$'\200'-$'\277']/}
  w=${#s}
}
level() { # $1 = how much detail: 0 wide, 1 compact, 2 tight, 3 minimal
  narrow="" gap="   " width=20 lbar=10 sep="  ${dim}│${reset}  " full_msg=" limit reached" out_msg="runs out in" wgap="  " old="(~ last known)" icon="⏱ "
  [ $1 -ge 1 ] && narrow=1 gap=" " width=10 sep=" ${dim}│${reset} " full_msg="" out_msg="out in" wgap=" " old="(~ old)"
  [ $1 -ge 2 ] && width=5 lbar=5
  [ $1 -ge 3 ] && width=0 lbar=0 out_msg="out" icon="" old="" # just the "~", no legend
}

build1() { # line 1: model and this session's context window (live only, never cached)
  local m="" cx=""
  [ -n "$model" ] && m="${bold}◆ ${model}${reset}"
  if [ "$ctx" != - ]; then
    paint $ctx; cx="context "
    [ $width -gt 0 ] && bar $ctx $width && cx+="${b} "
    cx+="${c}${ctx}%${reset}"
  fi
  # Claude Code cuts an overflowing line off at the end, so at the minimal level the context
  # goes first and a long model name is what gets cut.
  if [ $width -eq 0 ]; then line="${cx}${cx:+${m:+$gap}}${m}"; else line="${m}${m:+${cx:+$gap}}${cx}"; fi
  # A line with content starts with a reset: Claude Code dims the whole line, and without it only
  # the text before the first reset would come out dimmed. An empty line must stay empty.
  [ -n "$line" ] && line="${reset}${line}"
  [ "$ctx" = - ] && return
  if [ -z "$narrow" ] && [ "$ctx_used" != - ] && [ "$ctx_size" != - ] && [ "$ctx_size" -gt 0 ]; then
    tokens $ctx_used; line+="   ${dim}${t} used · "
    tokens $(( ctx_size > ctx_used ? ctx_size - ctx_used : 0 )); line+="${t} free${reset}"
  fi
}
build2() { # line 2: subscription limits, each with a reset countdown and a run-out warning
  line=""
  limit "5h" "$five" "$five_at" 18000 "$five10" "$five_c"
  limit "week" "$week" "$week_at" 604800 "$week10" "$week_c"
  [ -n "$line" ] || return
  line="${reset}${icon}${line}"
  [ -n "$cached" ] && [ -n "$old" ] && line+="${wgap}${dim}${old}${reset}"
}
fit() { # $1 = build1 or build2; sets $line at the most detailed level that fits $cols (wide when unknown)
  local lvl=0
  if [ "$cols" != - ] && [ "$cols" -gt 0 ]; then
    while [ $lvl -lt 3 ]; do
      colours off; level $lvl; $1; vis "$line"; [ $w -le $cols ] && break
      lvl=$(( lvl + 1 ))
    done
  fi
  colours on; level $lvl; $1
}

fit build1; line1=$line
fit build2; line2=$line
printf '%s' "${line1}${line1:+${line2:+$'\n'}}${line2}"
