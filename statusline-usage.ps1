# Status line, two lines: the model and context window use, then the 5-hour and 7-day
# subscription limits with reset countdowns, warning when the pace would run a limit out early.
# PowerShell port of statusline-usage.sh for Windows without Git Bash. Prints the same output,
# shares the same cache file, and needs no jq. Runs on Windows PowerShell 5.1 and PowerShell 7.
# Non-ASCII glyphs are written as character codes so the file parses the same in every version.
$ErrorActionPreference = 'SilentlyContinue'
$utf8 = New-Object System.Text.UTF8Encoding $false

# Read stdin as raw UTF-8 bytes, so the console code page can't mangle anything.
$ms = New-Object System.IO.MemoryStream
[Console]::OpenStandardInput().CopyTo($ms)
$raw = $utf8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)

function Num($v) { # a plain integer of at most 12 digits, or $null for anything else
  if ($v -is [string] -and $v -match '^[0-9]{1,12}$') { return [long]$v }
  return $null
}
function IDiv([long]$a, [long]$b) { # integer division, like bash's $(( a / b ))
  $r = [long]0
  return [Math]::DivRem($a, $b, [ref]$r)
}
# Looked up by name: System.Numerics isn't always loaded in Windows PowerShell 5.1.
$numericTypes = 'System.Int32', 'System.Int64', 'System.Double', 'System.Decimal', 'System.Single', 'System.Int16',
  'System.UInt16', 'System.UInt32', 'System.UInt64', 'System.Byte', 'System.SByte', 'System.Numerics.BigInteger' |
  ForEach-Object { $_ -as [type] } | Where-Object { $_ }
function IsNumber($x) {
  if ($null -eq $x) { return $false }
  foreach ($t in $numericTypes) { if ($x -is $t) { return $true } }
  return $false
}
function N($x, [int]$scale) { # like the bash version's jq n() (scale 1) and n10() (scale 10)
  if (-not (IsNumber $x)) { return $null }
  $v = [double]$x * $scale
  if ([double]::IsNaN($v) -or [double]::IsInfinity($v)) { return $null }
  if ($v -lt 0) { $v = 0 }
  if ($scale -eq 1) { $v = [Math]::Floor($v + 0.5) } else { $v = [Math]::Floor($v) }
  if ($v -ge 1e12) { return $null }
  return [long]$v
}
function Field($o, [string[]]$path) { # walks objects only, so a string or array along the way gives $null
  foreach ($k in $path) {
    if ($o -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $p = $o.PSObject.Properties[$k]
    if ($null -eq $p) { return $null }
    $o = $p.Value
  }
  return , $o
}

$now = Num $env:STATUSLINE_NOW # pins the clock for tests
if ($null -eq $now) { $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$cols = Num $env:COLUMNS # terminal width, set by Claude Code; 0 or unset means unknown

$j = $null
try { $j = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $j = $null }
$five = N (Field $j 'rate_limits', 'five_hour', 'used_percentage') 1
$five_at = N (Field $j 'rate_limits', 'five_hour', 'resets_at') 1
$week = N (Field $j 'rate_limits', 'seven_day', 'used_percentage') 1
$week_at = N (Field $j 'rate_limits', 'seven_day', 'resets_at') 1
$five10 = N (Field $j 'rate_limits', 'five_hour', 'used_percentage') 10
$week10 = N (Field $j 'rate_limits', 'seven_day', 'used_percentage') 10
$ctx = N (Field $j 'context_window', 'used_percentage') 1
$ctx_size = N (Field $j 'context_window', 'context_window_size') 1
$ctx_used = $null
$cu = Field $j 'context_window', 'current_usage'
if ($cu -is [System.Management.Automation.PSCustomObject]) {
  # jq adds these with null counting as 0; any other non-number makes the sum invalid
  $sum = [double]0; $seen = $false; $bad = $false
  foreach ($k in 'input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens') {
    $v = Field $cu $k
    if ($null -eq $v) { continue }
    if (IsNumber $v) { $sum += [double]$v; $seen = $true } else { $bad = $true }
  }
  if ($seen -and -not $bad) { $ctx_used = N $sum 1 }
}
$model = ''
$mv = Field $j 'model', 'display_name'
if ($null -ne $mv -and $mv -isnot [bool]) { $model = [string]$mv } elseif ($mv -eq $true) { $model = 'true' }
$model = $model -replace '[\x00-\x1f\x7f-\x9f]', ''
$live = ($null -ne $five) -or ($null -ne $week)

# Cache the last known values so the bars show at session start, before the first reply.
# A live window wins; a cached one is used only while its reset time is still ahead.
$homeDir = $env:HOME
if (-not $homeDir -or -not (Test-Path -LiteralPath $homeDir -PathType Container)) { $homeDir = $HOME }
$cache = Join-Path (Join-Path (Join-Path $homeDir '.claude') 'cache') 'statusline-usage.cache'
$c5 = $null; $c5_at = $null; $cw = $null; $cw_at = $null
$cached = $false; $five_c = $false; $week_c = $false
if (Test-Path -LiteralPath $cache -PathType Leaf) {
  try {
    $first = ([IO.File]::ReadAllText($cache, $utf8) -split "`n", 2)[0].Trim(" `t".ToCharArray())
    if ($first -ne '') {
      $parts = @($first -split '[ \t]+', 4) # like bash read: the last field takes the rest
      if ($parts.Count -gt 0) { $c5 = Num $parts[0] }
      if ($parts.Count -gt 1) { $c5_at = Num $parts[1] }
      if ($parts.Count -gt 2) { $cw = Num $parts[2] }
      if ($parts.Count -gt 3) { $cw_at = Num $parts[3] }
    }
  } catch { }
}
if ($null -eq $five -and $null -ne $c5 -and $null -ne $c5_at -and $c5_at -gt $now) { $five = $c5; $five_at = $c5_at; $five10 = $null; $five_c = $true; $cached = $true }
if ($null -eq $week -and $null -ne $cw -and $null -ne $cw_at -and $cw_at -gt $now) { $week = $cw; $week_at = $cw_at; $week10 = $null; $week_c = $true; $cached = $true }

function D($v) { if ($null -eq $v) { return '-' } return "$v" }
$new = "$(D $five) $(D $five_at) $(D $week) $(D $week_at)"
$old = "$(D $c5) $(D $c5_at) $(D $cw) $(D $cw_at)"
if ($live -and -not (Test-Path -LiteralPath $cache -PathType Container) -and $new -ne $old) {
  $tmp = "$cache.$PID" # per-process temp file, so parallel sessions never collide
  try {
    $dir = Split-Path -Parent $cache
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
    # temp files left by runs that were killed outright
    Get-ChildItem -LiteralPath $dir -Filter 'statusline-usage.cache.*' -File |
      Where-Object { $_.Name -match '^statusline-usage\.cache\.[0-9]' } | Remove-Item -Force
    [IO.File]::WriteAllText($tmp, "$new`n", $utf8)
    Move-Item -LiteralPath $tmp -Destination $cache -Force -ErrorAction Stop
  } catch { Remove-Item -LiteralPath $tmp -Force }
}

$E = [char]27
$G = @{ diamond = [string][char]0x25C6; full = [string][char]0x2588; track = [string][char]0x2591; timer = [string][char]0x23F1
  reset = [string][char]0x21BB; warn = [string][char]0x26A0; pipe = [string][char]0x2502; dot = [string][char]0x00B7 }
$eighths = @('', [string][char]0x258F, [string][char]0x258E, [string][char]0x258D, [string][char]0x258C, [string][char]0x258B, [string][char]0x258A, [string][char]0x2589)

function Colours([bool]$on) { # off is used to measure a line's width
  if ($on) {
    $script:dim = "$E[2m"; $script:bold = "$E[1m"; $script:green = "$E[32m"; $script:yellow = "$E[33m"; $script:red = "$E[31m"; $script:rst = "$E[0m"
  } else { $script:dim = ''; $script:bold = ''; $script:green = ''; $script:yellow = ''; $script:red = ''; $script:rst = '' }
}
function Tokens([long]$n) { # e.g. "850", "145k", "1.2M" or "1M"
  $tenths = IDiv ($n + 50000) 100000
  if ($n -lt 1000) { return "$n" }
  if ($n -lt 999500) { return "$(IDiv ($n + 500) 1000)k" }
  if ($tenths % 10 -eq 0) { return "$(IDiv $tenths 10)M" }
  return "$(IDiv $tenths 10).$($tenths % 10)M"
}
function Paint([long]$p) { # green under 50, yellow under 80, red above
  if ($p -ge 80) { return $script:red }
  if ($p -ge 50) { return $script:yellow }
  return $script:green
}
function Dur([long]$sec) { # e.g. "1d 2h 3m", zero units dropped, minutes rounded up (no minutes past a day when narrow)
  $m = IDiv ($sec + 59) 60; $d = IDiv $m 1440; $h = IDiv ($m % 1440) 60; $m = $m % 60
  $parts = @()
  if ($d -gt 0) { $parts += "${d}d" }
  if ($h -gt 0) { $parts += "${h}h" }
  if ($m -gt 0 -and (-not $script:narrow -or $d -eq 0)) { $parts += "${m}m" }
  if ($parts.Count -eq 0) { return '0m' }
  return $parts -join ' '
}
function Bar([long]$p, [int]$width, [string]$c) { # smooth fill in $c (1/8-cell steps) on a dim track
  if ($p -gt 100) { $p = 100 }
  $e = IDiv ($p * $width * 8 + 50) 100; $full = IDiv $e 8
  $on = $G.full * $full
  if ($e % 8 -gt 0) { $on += $eighths[$e % 8]; $full++ }
  $off = $G.track * [Math]::Max(0, $width - $full)
  return "$c$on$($script:rst)$($script:dim)$off$($script:rst)"
}
function Limit($label, $p, $resetsAt, [long]$window, $p10, [bool]$fromCache) { # one window's segment, or ''
  if ($null -eq $p) { return '' }
  if ($null -eq $p10) { $p10 = $p * 10 } # cached values carry no tenths
  $seg = ''
  if ($fromCache) { $seg = "$($script:dim)~$($script:rst)" } # marks this window as last known
  $c = Paint $p
  $seg += "$label "
  if ($script:lbar -gt 0) { $seg += (Bar $p $script:lbar $c) + ' ' }
  $seg += "$c$p%$($script:rst)"
  if ($null -ne $resetsAt -and $resetsAt -gt $now) {
    $left = $resetsAt - $now; $elapsed = $window - $left
    $seg += " $($script:dim)$($G.reset) $(Dur $left)$($script:rst)"
    # Warn only when the pace so far (used x window / elapsed, in tenths of a percent so rounding
    # can't trigger it) runs out more than a minute before the reset. Skipped in the first 5% of
    # the window, where the pace is mostly noise.
    if ($p10 -ge 1000) { $seg += "$($script:wgap)$($script:red)$($G.warn)$($script:full_msg)$($script:rst)" }
    elseif ($p10 -gt 0 -and $elapsed -ge (IDiv $window 20)) {
      $out = IDiv ((1000 - $p10) * $elapsed) $p10
      if ($out -lt ($left - 60)) {
        $o = $out; if ($o -le 0) { $o = 1 }
        $seg += "$($script:wgap)$($script:red)$($G.warn) $($script:out_msg) $(Dur $o)$($script:rst)"
      }
    }
  }
  return $seg
}
function Vis([string]$s) { # width in characters (a surrogate pair counts once)
  $n = 0
  foreach ($ch in $s.ToCharArray()) { if (-not [char]::IsLowSurrogate($ch)) { $n++ } }
  return $n
}
function Level([int]$l) { # how much detail: 0 wide, 1 compact, 2 tight, 3 minimal
  $script:narrow = $false; $script:gap = '   '; $script:width = 20; $script:lbar = 10
  $script:sep = "  $($script:dim)$($G.pipe)$($script:rst)  "; $script:full_msg = ' limit reached'; $script:out_msg = 'runs out in'
  $script:wgap = '  '; $script:old = '(~ last known)'; $script:icon = "$($G.timer) "
  if ($l -ge 1) {
    $script:narrow = $true; $script:gap = ' '; $script:width = 10; $script:sep = " $($script:dim)$($G.pipe)$($script:rst) "
    $script:full_msg = ''; $script:out_msg = 'out in'; $script:wgap = ' '; $script:old = '(~ old)'
  }
  if ($l -ge 2) { $script:width = 5; $script:lbar = 5 }
  if ($l -ge 3) { $script:width = 0; $script:lbar = 0; $script:out_msg = 'out'; $script:icon = ''; $script:old = '' }
}

function Build1 { # line 1: model and this session's context window (live only, never cached)
  $m = ''; $cx = ''
  if ($model) { $m = "$($script:bold)$($G.diamond) $model$($script:rst)" }
  if ($null -ne $ctx) {
    $c = Paint $ctx; $cx = 'context '
    if ($script:width -gt 0) { $cx += (Bar $ctx $script:width $c) + ' ' }
    $cx += "$c$ctx%$($script:rst)"
  }
  # Claude Code cuts an overflowing line off at the end, so at the minimal level the context
  # goes first and a long model name is what gets cut.
  if ($script:width -eq 0) { $first = $cx; $second = $m } else { $first = $m; $second = $cx }
  $line = $first
  if ($first -and $second) { $line += $script:gap }
  $line += $second
  # A line with content starts with a reset: Claude Code dims the whole line, and without it only
  # the text before the first reset would come out dimmed. An empty line must stay empty.
  if ($line) { $line = "$($script:rst)$line" }
  if ($null -eq $ctx) { return $line }
  if (-not $script:narrow -and $null -ne $ctx_used -and $null -ne $ctx_size -and $ctx_size -gt 0) {
    $free = 0; if ($ctx_size -gt $ctx_used) { $free = $ctx_size - $ctx_used }
    $line += "   $($script:dim)$(Tokens $ctx_used) used $($G.dot) $(Tokens $free) free$($script:rst)"
  }
  return $line
}
function Build2 { # line 2: subscription limits, each with a reset countdown and a run-out warning
  $segs = @(
    (Limit '5h' $five $five_at 18000 $five10 $five_c),
    (Limit 'week' $week $week_at 604800 $week10 $week_c)
  ) | Where-Object { $_ }
  if (-not $segs) { return '' }
  $line = "$($script:rst)$($script:icon)" + ($segs -join $script:sep)
  if ($cached -and $script:old) { $line += "$($script:wgap)$($script:dim)$($script:old)$($script:rst)" }
  return $line
}
function Fit([scriptblock]$build) { # the most detailed level that fits $cols (wide when unknown)
  $lvl = 0
  if ($null -ne $cols -and $cols -gt 0) {
    while ($lvl -lt 3) {
      Colours $false; Level $lvl
      if ((Vis (& $build)) -le $cols) { break }
      $lvl++
    }
  }
  Colours $true; Level $lvl
  return & $build
}

$line1 = Fit ${function:Build1}
$line2 = Fit ${function:Build2}
# A spacer row between the two lines. It holds a reset code, because Claude Code may drop a
# row that is completely empty.
$text = $line1
if ($line1 -and $line2) { $text += "`n$E[0m`n" }
$text += $line2
$bytes = $utf8.GetBytes($text)
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
