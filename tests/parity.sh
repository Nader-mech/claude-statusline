#!/bin/bash
# Runs every implementation given on the command line against the same cases and checks that
# they print byte-identical output, and that a few outputs match what they must be.
#   tests/parity.sh "bash statusline-usage.sh" "pwsh -NoProfile -File statusline-usage.ps1"
# Each case gets a fresh HOME (and USERPROFILE, for Windows), a pinned clock and a set width.
set -u
cd "$(dirname "$0")/.."
[ $# -ge 1 ] || { echo "usage: $0 \"<command>\" [\"<command>\" ...]" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/statusline-parity.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
NOW=1800000000
fail=0 count=0

# name | stdin | COLUMNS | cache file contents ("" = no cache)
cases=()
add() { cases+=("$1"$'\x1f'"$2"$'\x1f'"$3"$'\x1f'"$4"); }
rl() { # $1 5h %, $2 5h secs left, $3 week %, $4 week secs left
  echo "\"rate_limits\":{\"five_hour\":{\"used_percentage\":$1,\"resets_at\":$((NOW + $2))},\"seven_day\":{\"used_percentage\":$3,\"resets_at\":$((NOW + $4))}}"
}
ctx() { echo "\"context_window\":{\"used_percentage\":$1,\"context_window_size\":$2,\"current_usage\":{\"input_tokens\":$3,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}}"; }
M='"model":{"display_name":"Opus 5.5"}'
LM='"model":{"display_name":"Claude Opus 4.7 (1M context)"}'
for cols in "" 0 40 60 80 100 200; do
  add "steady c=$cols"    "{$M,$(ctx 42 200000 84000),$(rl 35 9000 48 250000)}" "$cols" ""
  add "warnings c=$cols"  "{$LM,$(ctx 95 1000000 950000),$(rl 30 14400 40 500000)}" "$cols" ""
  add "full c=$cols"      "{$LM,$(ctx 99 1000000 990000),$(rl 100 3000 99 100000)}" "$cols" ""
  add "cached c=$cols"    "{$LM}" "$cols" "30 $((NOW + 14400)) 40 $((NOW + 500000))"
  add "mixed c=$cols"     "{$M,\"rate_limits\":{\"five_hour\":{\"used_percentage\":30,\"resets_at\":$((NOW + 3600))}}}" "$cols" "10 $((NOW + 3600)) 60 $((NOW + 90000))"
done
add "early window"       "{$M,$(rl 4.5 17100 0 597000)}" "" ""
add "99.96 percent"      "{$M,$(rl 99.96 17100 10 500000)}" "" ""
add "1 percent sliver"   "{$M,$(ctx 1 1000000 10000),$(rl 1 9000 0 500000)}" "" ""
add "over 100"           "{$M,$(ctx 130 200000 260000),$(rl 150 3000 0 500000)}" "" ""
add "small tokens"       "{$M,$(ctx 0 1000000 850)}" "" ""
add "token rounding"     "{$M,$(ctx 5 2000000 1950000)}" "" ""
add "model only"         "{$M}" "" ""
add "context only"       '{"context_window":{"used_percentage":20}}' "" ""
add "limits only"        "{$(rl 30 3600 0 500000)}" "" ""
add "empty object"       '{}' "" ""
add "invalid json"       'nope' "" ""
add "empty stdin"        '' "" ""
add "array"              '[]' "" ""
add "strings for numbers" "{$M,\"rate_limits\":{\"five_hour\":{\"used_percentage\":\"45\",\"resets_at\":\"soon\"}}}" "" ""
add "injection attempt"  "{\"model\":{\"display_name\":\"\$(touch pwned)\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":\"x[\$(touch pwned)]\",\"resets_at\":1}}}" "" ""
add "control chars"      '{"model":{"display_name":"Op\tus\u001b[31m 5"}}' "" ""
add "negative and huge"  "{$M,$(rl -5 3600 1e300 500000)}" "" ""
add "expired cache"      "{$M}" "" "30 $((NOW - 5)) 40 $((NOW + 500000))"
add "corrupt cache"      "{$M}" "" "abc def ghi jkl"
add "crlf cache"         "{$M}" "" "$(printf '30 %s 40 %s\r' $((NOW + 3600)) $((NOW + 500000)))"
add "cache old format"   "{$M}" "" "40 $((NOW + 3600)) 20"
add "leading zeros"      "{$M}" "" "08 $((NOW + 3600)) 09 $((NOW + 500000))"
add "long model name"   "{\"model\":{\"display_name\":\"$(printf '%.0sé' $(seq 4000))\"},$(rl 30 3600 0 500000)}" 80 ""
add "bidi and invisible" '{"model":{"display_name":"Op\u202eus\u200b 5\ufeff.5\u2066"}}' "" ""
add "null current_usage" '{"context_window":{"used_percentage":12,"context_window_size":200000,"current_usage":null}}' "" ""

run() { # $1 = command, $2 = case dir; prints the output bytes as hex so any difference shows
  local dir=$2 in cols cache home=$2/home
  in=$(cat "$dir/stdin"); cols=$(cat "$dir/cols")
  # On Windows (Git Bash) pass a native path, so PowerShell sees the same HOME as bash.
  command -v cygpath >/dev/null 2>&1 && home=$(cygpath -m "$home")
  ( cd "$dir/home" && printf '%s' "$in" | env HOME="$home" USERPROFILE="$home" STATUSLINE_NOW=$NOW COLUMNS="$cols" \
      $1 2>"$dir/stderr" ) | od -An -tx1 | tr -s ' \n' ' '
}

i=0
for c in "${cases[@]}"; do
  IFS=$'\x1f' read -r name in cols cache <<<"$c"
  i=$((i + 1)); count=$((count + 1))
  ref="" refcmd=""
  for cmd in "$@"; do
    dir="$work/$i.$(printf '%s' "$cmd" | cksum | cut -d' ' -f1)"
    mkdir -p "$dir/home/.claude/cache"
    printf '%s' "$in" > "$dir/stdin"; printf '%s' "$cols" > "$dir/cols"
    [ -n "$cache" ] && printf '%s\n' "$cache" > "$dir/home/.claude/cache/statusline-usage.cache"
    out=$(run "$cmd" "$dir")
    if [ -s "$dir/stderr" ]; then echo "FAIL [$name] $cmd wrote to stderr: $(head -c 300 "$dir/stderr")"; fail=$((fail + 1)); fi
    if [ -e "$dir/home/pwned" ]; then echo "FAIL [$name] $cmd ran injected code"; fail=$((fail + 1)); fi
    if [ -z "$refcmd" ]; then ref=$out refcmd=$cmd
    elif [ "$out" != "$ref" ]; then
      echo "FAIL [$name] output differs: '$refcmd' vs '$cmd'"
      echo "  $refcmd: $ref" | cut -c1-400; echo "  $cmd: $out" | cut -c1-400
      fail=$((fail + 1))
    fi
    # Outputs that must be exact, whatever the implementation.
    case $name in
      "empty object"|"invalid json"|"empty stdin"|"array")
        [ -z "$out" ] || [ "$out" = " " ] || { echo "FAIL [$name] $cmd should print nothing, got: $out"; fail=$((fail + 1)); } ;;
    esac
  done
done

echo "$count cases x $# implementations, $fail failures"
[ $fail -eq 0 ]
