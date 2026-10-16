# Installs the PowerShell status line into ~/.claude and points Claude Code's settings.json at it.
# For Windows without Git Bash, or anyone who'd rather not install jq. Run it from the repo folder:
#   powershell -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = 'Stop'
# Same home as the status line script: HOME when it names a real folder (Git Bash sets it), else $HOME.
$homeDir = $env:HOME
if (-not $homeDir -or -not (Test-Path -LiteralPath $homeDir -PathType Container)) { $homeDir = $HOME }
$dir = Join-Path $homeDir '.claude'
$settings = Join-Path $dir 'settings.json'
$script = Join-Path $dir 'statusline-usage.ps1'
$utf8 = New-Object System.Text.UTF8Encoding $false

# Forward slashes: Claude Code may run the command through Git Bash, which eats backslashes.
# Both bash and PowerShell expand $ and ` inside double quotes, and no single quoting style
# works in both, so a home path with those characters is refused rather than written unsafely.
$path = $script -replace '\\', '/'
if ($path -match '[$`"]') {
  Write-Error ("Your home folder path contains a `$, a backtick or a double quote, which would be unsafe in " +
    "the status line command. Copy statusline-usage.ps1 to $script and set statusLine in $settings by hand.")
  exit 1
}

# Check the existing settings before touching anything. An empty file counts as {}.
$json = New-Object PSObject
$hadSettings = $false
if (Test-Path -LiteralPath $settings) {
  $raw = [IO.File]::ReadAllText($settings)
  if ($raw.Trim()) {
    try { $json = $raw | ConvertFrom-Json } catch { $json = $null }
    if ($json -isnot [System.Management.Automation.PSCustomObject]) {
      Write-Error "$settings isn't a valid JSON object (a trailing comma or a comment?), so it was left alone. Fix it and run this again."
      exit 1
    }
    $hadSettings = $true
  }
}

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'statusline-usage.ps1') -Destination $script -Force

# Windows PowerShell ships with Windows; elsewhere this runs under PowerShell 7 (pwsh).
$exe = if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) { 'powershell' } else { 'pwsh' }
$command = "$exe -NoProfile -ExecutionPolicy Bypass -File `"$path`""
# refreshInterval redraws every 10 s so the countdown stays current while idle (Claude Code 2.1.97+).
$statusLine = [PSCustomObject]@{ type = 'command'; command = $command; refreshInterval = 10 }
$json | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLine -Force

# Each run keeps its own timestamped backup, so a second run never overwrites the first.
$backup = $null
if ($hadSettings) {
  # Invariant culture: some regions default to a non-Gregorian calendar (e.g. year 1448).
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
  $backup = "$settings.bak.$stamp"; $n = 1
  while (Test-Path -LiteralPath $backup) { $backup = "$settings.bak.$stamp.$n"; $n++ }
  Copy-Item -LiteralPath $settings -Destination $backup
}
# Build the new text first, then write it into the existing file once the backup is safe. Writing
# in place keeps a symlinked settings.json linked and keeps the file's permissions.
$content = $json | ConvertTo-Json -Depth 100
if (-not $content) { Write-Error 'Building the new settings failed; nothing was changed.'; exit 1 }
$isNew = -not (Test-Path -LiteralPath $settings)
[IO.File]::WriteAllText($settings, $content, $utf8)
if ($isNew -and -not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 7) {
  try { [IO.File]::SetUnixFileMode($settings, [IO.UnixFileMode]'UserRead, UserWrite') } catch { }
}

if ($backup) {
  Write-Output "Installed. Old settings saved to $backup"
  Write-Output 'If your settings.json had comments, they were dropped; the backup still has them.'
} else { Write-Output 'Installed.' }
Write-Output 'Start a new Claude Code session to see the status line.'
