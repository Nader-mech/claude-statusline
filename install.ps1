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

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'statusline-usage.ps1') -Destination $script -Force

$json = New-Object PSObject
if (Test-Path -LiteralPath $settings) {
  $raw = [IO.File]::ReadAllText($settings)
  if ($raw.Trim()) {
    try { $json = $raw | ConvertFrom-Json }
    catch { Write-Error "Couldn't read $settings as JSON, so it was left alone. Fix it and run this again."; exit 1 }
  }
  Copy-Item -LiteralPath $settings -Destination "$settings.bak" -Force
}

# Forward slashes: Claude Code may run the command through Git Bash, which eats backslashes.
# Windows PowerShell ships with Windows; elsewhere this runs under PowerShell 7 (pwsh).
$exe = if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) { 'powershell' } else { 'pwsh' }
$path = $script -replace '\\', '/'
$command = "$exe -NoProfile -ExecutionPolicy Bypass -File `"$path`""
# refreshInterval redraws every 10 s so the countdown stays current while idle (Claude Code 2.1.97+).
$statusLine = [PSCustomObject]@{ type = 'command'; command = $command; refreshInterval = 10 }
$json | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLine -Force
[IO.File]::WriteAllText($settings, ($json | ConvertTo-Json -Depth 100), $utf8)

Write-Output "Installed. Old settings saved to $settings.bak"
Write-Output 'Start a new Claude Code session to see the status line.'
