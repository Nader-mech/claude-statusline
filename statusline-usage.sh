#!/bin/bash
# Status line: subscription usage for the 5-hour window and the 7-day week.
# Runs on macOS, Linux, WSL and Git Bash. Needs jq.
input=$(cat)
cache="$HOME/.claude/cache/statusline-usage.cache"
dim=$'\033[2m' reset=$'\033[0m'

num() { # $1 = variable name; leaves a plain integer in it, or "-" for anything else
  local v=${!1}
  case $v in ''|*[!0-9]*) v=- ;; *) [ ${#v} -le 12 ] && v=$((10#$v)) || v=- ;; esac
  printf -v "$1" %s "$v"
}
now=${EPOCHSECONDS:-}; num now; [ "$now" = - ] && now=$(date +%s)

# One jq call: numbers are rounded to integers, anything else becomes "-",
# and control characters are stripped from the model name.
five= five_at= week= week_at= model=
j=$(jq -r '
  def n(p): (try p catch null) | if type == "number" then ([., 0] | max | . + 0.5 | floor | tostring) else "-" end;
  [ n(.rate_limits.five_hour.used_percentage), n(.rate_limits.five_hour.resets_at),
    n(.rate_limits.seven_day.used_percentage), n(.rate_limits.seven_day.resets_at),
    ((try .model.display_name catch null) // "" | tostring | gsub("[[:cntrl:]]"; "")) ] | join("\t")
' 2>/dev/null <<<"$input")
IFS=$'\t' read -r five five_at week week_at model <<<"$j"
model=${model%$'\r'} # native Windows jq.exe ends lines with CRLF
for v in five five_at week week_at; do num $v; done
live=""; [ "$five$week" != "--" ] && live=1

# Cache the last known values so the bars show at session start, before the first reply.
# A live window wins; a cached one is used only while its reset time is still ahead.
c5= c5_at= cw= cw_at= cached=""
[ -f "$cache" ] && [ -r "$cache" ] && read -r c5 c5_at cw cw_at 2>/dev/null < "$cache"
for v in c5 c5_at cw cw_at; do num $v; done
if [ "$five" = - ] && [ "$c5" != - ] && [ "$c5_at" != - ] && [ "$c5_at" -gt "$now" ]; then five=$c5 five_at=$c5_at cached=1; fi
if [ "$week" = - ] && [ "$cw" != - ] && [ "$cw_at" != - ] && [ "$cw_at" -gt "$now" ]; then week=$cw week_at=$cw_at cached=1; fi

new="$five $five_at $week $week_at"
if [ -n "$live" ] && [ ! -d "$cache" ] && [ "$new" != "$c5 $c5_at $cw $cw_at" ]; then
  tmp="$cache.$$" # per-process temp file, so parallel sessions never collide
  { [ -d "${cache%/*}" ] || mkdir -p "${cache%/*}"; printf '%s\n' "$new" > "$tmp" && mv -f "$tmp" "$cache"; } 2>/dev/null \
    || rm -f "$tmp" 2>/dev/null
fi

out=""
seg() { # $1 = label, $2 = percent, $3 = resets_at
  [ "$2" = - ] && return
  local p=$2 filled=$(( ($2 + 5) / 10 )) bar="" i c=$'\033[32m' when="" m d h
  [ $filled -gt 10 ] && filled=10
  for ((i = 0; i < 10; i++)); do [ $i -lt $filled ] && bar+="█" || bar+="░"; done
  [ $p -ge 50 ] && c=$'\033[33m'; [ $p -ge 80 ] && c=$'\033[31m' # green under 50, yellow under 80, red above
  if [ "$3" != - ] && [ "$3" -gt "$now" ]; then # time left, e.g. "1d 2h 3m"; zero units dropped, minutes rounded up
    m=$(( ($3 - now + 59) / 60 )); d=$(( m / 1440 )); h=$(( m % 1440 / 60 )); m=$(( m % 60 ))
    [ $d -gt 0 ] && when="${d}d"
    [ $h -gt 0 ] && when+="${when:+ }${h}h"
    [ $m -gt 0 ] && when+="${when:+ }${m}m"
  fi
  out+="${out:+  ·  }$c$1 $bar $p%$reset${when:+$dim resets in $when$reset}"
}
seg "5h" "$five" "$five_at"
seg "week" "$week" "$week_at"

[ -n "$cached" ] && out+="  $dim(last known)$reset"
[ -n "$model" ] && out+="${out:+  }$dim${out:+· }$model$reset"
printf '%s' "$out"
