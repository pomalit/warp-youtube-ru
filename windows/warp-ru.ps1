# Reconnects Cloudflare WARP (proxy mode, 127.0.0.1:40000) until YouTube sees a Russian IP.
# Usage:
#   powershell -ExecutionPolicy Bypass -File warp-ru.ps1              # reconnect until RU
#   powershell -ExecutionPolicy Bypass -File warp-ru.ps1 -Check       # only show current country
#   powershell -ExecutionPolicy Bypass -File warp-ru.ps1 -Install     # also run at every Windows login
#   powershell -ExecutionPolicy Bypass -File warp-ru.ps1 -Uninstall   # stop running at login
param(
    [switch]$Check,
    [switch]$Startup,
    [switch]$Install,
    [switch]$Uninstall,
    [int]$MaxTries = 40,
    [string]$Want = 'RU'
)

$proxy   = '127.0.0.1:40000'
$logDir  = Join-Path $env:LOCALAPPDATA 'warp-ru'
$logFile = Join-Path $logDir 'warp-ru.log'
$lnk     = Join-Path ([Environment]::GetFolderPath('Startup')) 'WARP YouTube RU.lnk'

$warp = (Get-Command warp-cli -ErrorAction SilentlyContinue).Source
if (-not $warp) { $warp = Join-Path $env:ProgramFiles 'Cloudflare\Cloudflare WARP\warp-cli.exe' }
if (-not (Test-Path $warp)) {
    Write-Host 'Cloudflare WARP is not installed. Run: winget install Cloudflare.Warp' -ForegroundColor Red
    exit 2
}

if ($Uninstall) {
    Remove-Item $lnk -ErrorAction SilentlyContinue
    Write-Host 'Removed from startup.'
    exit 0
}

if ($Install) {
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $s.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $s.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Startup"
    $s.WorkingDirectory = Split-Path $PSCommandPath
    $s.WindowStyle = 7
    $s.Save()
    Write-Host "Added to startup: $lnk"
    Write-Host "Log after each login: $logFile"
}

if ($Startup) {
    New-Item -ItemType Directory -Force $logDir | Out-Null
    Start-Transcript -Path $logFile -Force | Out-Null
    Write-Host (Get-Date)
    # wait up to 3 minutes for the internet to come up after login
    foreach ($i in 1..36) {
        if ((curl.exe -s -o NUL -w '%{http_code}' --max-time 5 https://www.youtube.com/) -match '^[23]') { break }
        Start-Sleep 5
    }
}

function Invoke-Warp { & $warp --accept-tos @args }

function Test-WarpConnected { [bool]((Invoke-Warp status) -match 'Status update: Connected') }

function Get-YouTubeCountry {
    $html = curl.exe -s --max-time 20 --socks5-hostname $proxy -H 'Accept-Language: en-US' https://www.youtube.com/
    ([regex]::Match("$html", '"GL":"([A-Z]{2})"')).Groups[1].Value
}

function Connect-Warp {
    Invoke-Warp disconnect | Out-Null
    Start-Sleep 2
    Invoke-Warp connect | Out-Null
    # wait for the proxy to come up
    foreach ($i in 1..15) {
        if (Test-WarpConnected) { break }
        Start-Sleep 1
    }
    Start-Sleep 3
}

# first run on this PC: create a free WARP registration
Invoke-Warp registration show *> $null
if ($LASTEXITCODE -ne 0) { Invoke-Warp registration new | Out-Null }

# make sure WARP never takes over the whole PC
if (-not ((Invoke-Warp settings) -match 'Mode: WarpProxy on port 40000')) {
    Invoke-Warp mode proxy | Out-Null
    Invoke-Warp proxy port 40000 | Out-Null
}

if (-not (Test-WarpConnected)) { Connect-Warp }

$country = Get-YouTubeCountry
Write-Host "YouTube sees: $country"
if ($country -eq $Want) { Write-Host "Good, already $Want." -ForegroundColor Green; exit 0 }
if ($Check) { exit 1 }

foreach ($try in 1..$MaxTries) {
    Connect-Warp
    $country = Get-YouTubeCountry
    Write-Host "try $try : $country"
    if ($country -eq $Want) {
        Write-Host "Got $Want. Stay connected (don't reconnect WARP) to keep it." -ForegroundColor Green
        exit 0
    }
}

Write-Host "No $Want address after $MaxTries tries. Try again later." -ForegroundColor Yellow
exit 1
