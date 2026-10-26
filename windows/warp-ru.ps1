# Reconnects Cloudflare WARP (proxy mode, 127.0.0.1:40000) until YouTube sees a Russian IP.
# Usage:
#   powershell -ExecutionPolicy Bypass -File warp-ru.ps1              # reconnect until RU
#   powershell -ExecutionPolicy Bypass -File warp-ru.ps1 -Check       # only show current country
#   powershell -ExecutionPolicy Bypass -File warp-ru.ps1 -Install     # keep it RU: check at login, after wake, every 10 minutes
#   powershell -ExecutionPolicy Bypass -File warp-ru.ps1 -Uninstall   # stop the automatic checks
param(
    [switch]$Check,
    [switch]$Startup,
    [switch]$Install,
    [switch]$Uninstall,
    [int]$MaxTries = 40,
    [string]$Want = 'RU'
)

$proxy    = '127.0.0.1:40000'
$logDir   = Join-Path $env:LOCALAPPDATA 'warp-ru'
$logFile  = Join-Path $logDir 'warp-ru.log'
$taskName = 'WARP YouTube RU'
# older versions ran from a Startup-folder shortcut instead of a scheduled task
$lnk      = Join-Path ([Environment]::GetFolderPath('Startup')) 'WARP YouTube RU.lnk'

$warp = (Get-Command warp-cli -ErrorAction SilentlyContinue).Source
if (-not $warp) { $warp = Join-Path $env:ProgramFiles 'Cloudflare\Cloudflare WARP\warp-cli.exe' }
if (-not (Test-Path $warp)) {
    Write-Host 'Cloudflare WARP is not installed. Run: winget install Cloudflare.Warp' -ForegroundColor Red
    exit 2
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $lnk -ErrorAction SilentlyContinue
    Write-Host 'Removed the automatic checks.'
    exit 0
}

if ($Install) {
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # conhost --headless keeps a console window from flashing up every 10 minutes
    $action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\conhost.exe') `
        -Argument "--headless `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Startup" `
        -WorkingDirectory (Split-Path $PSCommandPath)
    $user  = "$env:USERDOMAIN\$env:USERNAME"
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $user
    $every = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
    # wake from sleep (107) or Modern Standby (507); WARP often reconnects then
    $wake = New-CimInstance -ClientOnly -CimClass (Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskEventTrigger)
    $wake.Enabled = $true
    $wake.Delay = 'PT30S'
    $wake.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">' +
        "*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=107 or EventID=507)]]" +
        '</Select></Query></QueryList>'
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $logon, $every, $wake `
        -Settings $settings -Principal $principal -Force | Out-Null
    Remove-Item $lnk -ErrorAction SilentlyContinue
    Write-Host "Added scheduled task '$taskName': checks at login, after wake and every 10 minutes."
    Write-Host "Log: $logFile"
}

function Write-Log([string]$msg) {
    Write-Host $msg
    if ($Startup) { Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" }
}

if ($Startup) {
    New-Item -ItemType Directory -Force $logDir | Out-Null
    # one line per check; keep the last 1000
    if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 200KB) {
        $tail = Get-Content $logFile -Tail 1000
        Set-Content -Path $logFile -Value $tail
    }
    # wait up to 3 minutes for the internet to come up after login or wake
    $online = $false
    foreach ($i in 1..36) {
        if ((curl.exe -s -o NUL -w '%{http_code}' --max-time 5 https://www.youtube.com/generate_204) -match '^2') { $online = $true; break }
        Start-Sleep 5
    }
    if (-not $online) { Write-Log 'No internet, skipped.'; exit 0 }
}

function Invoke-Warp { & $warp --accept-tos @args }

function Test-WarpConnected { [bool]((Invoke-Warp status) -match 'Status update: Connected') }

function Get-YouTubeCountry {
    # sw.js_data is ~3 KB and starts with the country YouTube sees; the front page is ~1 MB
    $data = curl.exe -s --max-time 20 --socks5-hostname $proxy -H 'Accept-Language: en-US' https://www.youtube.com/sw.js_data
    $m = [regex]::Match("$data", '"yt\.sw\.adr",null,\[\[\["[^"]*","([A-Z]{2})"')
    if ($m.Success) { return $m.Groups[1].Value }
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
# a slow answer is not a reason to reconnect
if (-not $country) { Start-Sleep 5; $country = Get-YouTubeCountry }
Write-Log "YouTube sees: $country"
if ($country -eq $Want) { Write-Host "Good, already $Want." -ForegroundColor Green; exit 0 }
if ($Check) { exit 1 }

foreach ($try in 1..$MaxTries) {
    Connect-Warp
    $country = Get-YouTubeCountry
    Write-Log "try $try : $country"
    if ($country -eq $Want) {
        Write-Host "Got $Want. Stay connected (don't reconnect WARP) to keep it." -ForegroundColor Green
        exit 0
    }
}

Write-Log "No $Want address after $MaxTries tries. Try again later."
exit 1
