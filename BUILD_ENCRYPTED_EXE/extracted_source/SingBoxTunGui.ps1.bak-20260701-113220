# SingBoxTunGui.ps1 (FULL / FIXED)
# - sing-box latest via GitHub API
# - Wintun via wintun.net (robust) + SHA256 verification + HttpClient (proxy+UA)
# - Resizable UI (dynamic layout)
# - Robust ss:// parsing + auto-prepend scheme
# - Start/Stop + watchdog + network cleanup

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
try { Add-Type -AssemblyName System.Net.Http } catch {}

Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --------------------------
# Paths
# --------------------------
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir     = Join-Path $scriptDir "bin"
$singBoxExe = Join-Path $binDir "sing-box.exe"
$wintunDll  = Join-Path $binDir "wintun.dll"

$configPath = Join-Path $scriptDir "sing-box.json"
$appLogPath = Join-Path $scriptDir "app.log"
$stdoutPath = Join-Path $scriptDir "singbox.stdout.log"
$stderrPath = Join-Path $scriptDir "singbox.stderr.log"

New-Item -ItemType Directory -Path $binDir -Force | Out-Null

# --------------------------
# Logging helpers
# --------------------------
function New-Timestamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff") }

function Write-AppLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (New-Timestamp), $Level, $Message
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($appLogPath, $line + [Environment]::NewLine, $enc)
}

function Ensure-File {
    param([Parameter(Mandatory=$true)][string]$Path)
    $enc = New-Object System.Text.UTF8Encoding($false)
    if (-not (Test-Path $Path)) { [System.IO.File]::WriteAllText($Path, "", $enc) }
}

# --------------------------
# Global exception handlers
# --------------------------
try {
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try {
            $msg = $e.Exception.ToString()
            try { Write-AppLog "ThreadException: $msg" "ERROR" } catch {}
            [System.Windows.Forms.MessageBox]::Show($msg, "Unhandled UI exception", "OK", "Error") | Out-Null
        } catch {}
    })
} catch {}

try {
    [AppDomain]::CurrentDomain.add_UnhandledException({
        param($sender, $e)
        try {
            $ex = $e.ExceptionObject
            $msg = if ($ex) { $ex.ToString() } else { "Unknown unhandled exception." }
            try { Write-AppLog "UnhandledException: $msg" "ERROR" } catch {}
            [System.Windows.Forms.MessageBox]::Show($msg, "Unhandled exception", "OK", "Error") | Out-Null
        } catch {}
    })
} catch {}

# --------------------------
# Admin check
# --------------------------
function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $false }
}

# --------------------------
# Network cleanup
# --------------------------
function Remove-SingBoxTunRoutes {
    param([string]$Pattern = "singbox-tun*")

    try {
        $routes4 = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -like $Pattern }
        foreach ($r in $routes4) {
            try {
                Remove-NetRoute -DestinationPrefix $r.DestinationPrefix -InterfaceIndex $r.InterfaceIndex -NextHop $r.NextHop -PolicyStore ActiveStore -Confirm:$false -ErrorAction SilentlyContinue
            } catch {}
        }
    } catch {}

    try {
        $routes6 = Get-NetRoute -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -like $Pattern }
        foreach ($r in $routes6) {
            try {
                Remove-NetRoute -DestinationPrefix $r.DestinationPrefix -InterfaceIndex $r.InterfaceIndex -NextHop $r.NextHop -PolicyStore ActiveStore -Confirm:$false -ErrorAction SilentlyContinue
            } catch {}
        }
    } catch {}
}

function Remove-LingeringSingBoxTunAdapters {
    param([string]$Pattern = "singbox-tun*")

    $adapters = @()
    try { $adapters = Get-NetAdapter -Name $Pattern -ErrorAction SilentlyContinue } catch { $adapters = @() }

    foreach ($a in $adapters) {
        try { Disable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

        $pnpId = $null
        try { $pnpId = $a.PnPDeviceID } catch { $pnpId = $null }

        if ($pnpId) {
            if (Get-Command Remove-PnpDevice -ErrorAction SilentlyContinue) {
                try { Remove-PnpDevice -InstanceId $pnpId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
            } elseif (Get-Command pnputil.exe -ErrorAction SilentlyContinue) {
                try { & pnputil.exe /remove-device "$pnpId" | Out-Null } catch {}
            }
        }
    }
}

function Reset-SingBoxNetworkState {
    if (-not (Test-IsAdmin)) { throw "Administrator privileges are required." }
    Remove-SingBoxTunRoutes -Pattern "singbox-tun*"
    Remove-LingeringSingBoxTunAdapters -Pattern "singbox-tun*"
    Start-Sleep -Milliseconds 300
}

# --------------------------
# HTTP helpers (HttpClient + proxy)
# --------------------------
function New-HttpClient {
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

    # Use system proxy (important in corporate environments)
    try {
        $handler.UseProxy = $true
        $handler.Proxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($handler.Proxy) {
            $handler.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        }
        $handler.UseDefaultCredentials = $true
    } catch {}

    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(60)

    # Browser-like headers
    $client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36") | Out-Null
    $client.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "*/*") | Out-Null
    $client.DefaultRequestHeaders.TryAddWithoutValidation("Accept-Language", "en-US,en;q=0.9") | Out-Null
    return $client
    } catch {
        # Fallback: HttpClient not available (old PowerShell/.NET). Caller will use WebClient/Invoke-WebRequest.
        return $null
    }
}

function Http-GetString {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [string]$Referer
    )
    $c = New-HttpClient
    if (-not $c) {
        try {
            if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
                $h = @{}
                if ($Referer) { $h['Referer'] = $Referer }
                return (Invoke-WebRequest -Uri $Url -Headers $h -UseBasicParsing).Content
            }
        } catch {}
        $wc = New-Object System.Net.WebClient
        if ($Referer) { $wc.Headers['Referer'] = $Referer }
        $wc.Headers['User-Agent'] = 'Mozilla/5.0'
        return $wc.DownloadString($Url)
    }
    try {
        if ($Referer) { $c.DefaultRequestHeaders.Referrer = [Uri]$Referer }
        return $c.GetStringAsync($Url).GetAwaiter().GetResult()
    } finally {
        try { $c.Dispose() } catch {}
    }
}

function Http-DownloadFile {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile,
        [string]$Referer
    )
    Write-AppLog "Downloading: $Url -> $OutFile" "INFO"
    $c = New-HttpClient
    if (-not $c) {
        try {
            $wc = New-Object System.Net.WebClient
            if ($Referer) { $wc.Headers['Referer'] = $Referer }
            $wc.Headers['User-Agent'] = 'Mozilla/5.0'
            $wc.DownloadFile($Url, $OutFile)
            return
        } catch {
            throw $_
        }
    }
    try {
        if ($Referer) { $c.DefaultRequestHeaders.Referrer = [Uri]$Referer }

        $resp = $c.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) {
            throw "HTTP $([int]$resp.StatusCode) $($resp.ReasonPhrase)"
        }

        $fs = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $resp.Content.CopyToAsync($fs).GetAwaiter().GetResult()
        } finally {
            $fs.Dispose()
        }
    } catch {
        throw "Download failed. URL='$Url'. Error=$($_.Exception.Message)"
    } finally {
        try { $c.Dispose() } catch {}
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $h = Get-FileHash -Algorithm SHA256 -Path $Path
    return ($h.Hash.ToLowerInvariant())
}

function Expand-ZipFile {
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    if (Test-Path $Destination) { Remove-Item -Recurse -Force $Destination -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force
}

# --------------------------
# GitHub JSON (sing-box)
# --------------------------
function Invoke-GitHubJson {
    param([Parameter(Mandatory=$true)][string]$ApiUrl)

    $c = New-HttpClient
    try {
        $c.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/vnd.github+json") | Out-Null
        return ($c.GetStringAsync($ApiUrl).GetAwaiter().GetResult() | ConvertFrom-Json)
    } catch {
        throw "GitHub API request failed. Api='$ApiUrl'. Error=$($_.Exception.Message)."
    } finally {
        try { $c.Dispose() } catch {}
    }
}

function Get-SingBoxLatestRelease {
    $api = "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    $json = Invoke-GitHubJson -ApiUrl $api

    $version = [string]$json.tag_name
    $asset = $json.assets | Where-Object { $_.name -match "windows-amd64\.zip$" } | Select-Object -First 1
    if (-not $asset) { throw "Could not find sing-box windows-amd64.zip in latest release." }

    @{ url = [string]$asset.browser_download_url; version = $version }
}

# --------------------------
# Wintun fetch (robust + verified)
# --------------------------
function Get-WintunLatestRelease {
    # Primary: parse official page for version + sha256
    # Fallback: known official (0.14.1) + sha256 (from official page)
    # Official page mentions 0.14.1 and the SHA2-256. :contentReference[oaicite:2]{index=2}

    $fallbackVer  = "0.14.1"
    $fallbackSha  = "07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51"
    $page         = "https://www.wintun.net/"
    $referer      = "https://www.wintun.net/"

    try {
        $html = Http-GetString -Url $page -Referer $referer

        # Extract "Wintun 0.14.1" and SHA2-256 hash
        $mVer = [regex]::Match($html, 'Wintun\s+(?<ver>\d+(?:\.\d+)+)', 'IgnoreCase')
        $mSha = [regex]::Match($html, 'SHA2-256:\s*`?(?<sha>[0-9a-f]{64})', 'IgnoreCase')

        $ver = if ($mVer.Success) { $mVer.Groups["ver"].Value } else { $fallbackVer }
        $sha = if ($mSha.Success) { $mSha.Groups["sha"].Value.ToLowerInvariant() } else { $fallbackSha }

        $url = "https://www.wintun.net/builds/wintun-$ver.zip"
        return @{ url = $url; version = $ver; sha256 = $sha; referer = $referer }
    } catch {
        Write-AppLog "Wintun page parse failed, using fallback 0.14.1. Reason: $($_.Exception.Message)" "WARN"
        $url = "https://www.wintun.net/builds/wintun-$fallbackVer.zip"
        return @{ url = $url; version = $fallbackVer; sha256 = $fallbackSha; referer = $referer }
    }
}

# --------------------------
# Ensure dependencies
# --------------------------
function Ensure-Dependencies {
    if (-not (Test-Path $singBoxExe)) {
        $rel = Get-SingBoxLatestRelease
        $tmpZip  = Join-Path $env:TEMP ("singbox_{0}.zip" -f $rel.version)
        $extract = Join-Path $env:TEMP ("singbox_{0}" -f $rel.version)

        try {
            Http-DownloadFile -Url $rel.url -OutFile $tmpZip -Referer "https://github.com/"
            Expand-ZipFile -ZipPath $tmpZip -Destination $extract

            $exe = Get-ChildItem -Path $extract -Recurse -Filter "sing-box.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $exe) { throw "sing-box.exe not found inside the zip." }

            Copy-Item $exe.FullName $singBoxExe -Force
            Write-AppLog "Installed sing-box: $($rel.version)" "INFO"
        } finally {
            try { Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue } catch {}
            try { Remove-Item -Recurse -Force $extract -ErrorAction SilentlyContinue } catch {}
        }
    }

    if (-not (Test-Path $wintunDll)) {
        $w = Get-WintunLatestRelease
        $tmpZip  = Join-Path $env:TEMP ("wintun_{0}.zip" -f $w.version)
        $extract = Join-Path $env:TEMP ("wintun_{0}" -f $w.version)

        try {
            Http-DownloadFile -Url $w.url -OutFile $tmpZip -Referer $w.referer

            $hash = Get-FileSha256 -Path $tmpZip
            if ($hash -ne $w.sha256) {
                throw "Wintun SHA256 mismatch. Expected=$($w.sha256) Got=$hash. Download may be blocked/altered by proxy."
            }

            Expand-ZipFile -ZipPath $tmpZip -Destination $extract

            $dll = Get-ChildItem -Path $extract -Recurse -Filter "wintun.dll" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "(\\|/)amd64(\\|/)" -or $_.FullName -match "(\\|/)x64(\\|/)" } |
                Select-Object -First 1

            if (-not $dll) {
                $dll = Get-ChildItem -Path $extract -Recurse -Filter "wintun.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if (-not $dll) { throw "wintun.dll not found inside the Wintun zip." }

            Copy-Item $dll.FullName $wintunDll -Force
            Write-AppLog "Installed Wintun: $($w.version) (sha256 OK)" "INFO"
        } finally {
            try { Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue } catch {}
            try { Remove-Item -Recurse -Force $extract -ErrorAction SilentlyContinue } catch {}
        }
    }
}

# --------------------------
# ss:// parsing
# --------------------------
function Remove-HiddenChars {
    param([Parameter(Mandatory=$true)][string]$s)
    return ($s -replace "[\uFEFF\u200B\u200C\u200D]", "").Trim()
}

function Decode-Base64UrlUtf8 {
    param([Parameter(Mandatory=$true)][string]$s)

    $t = $s.Trim()
    $t = $t.Replace("-", "+").Replace("_", "/")
    $mod = $t.Length % 4
    if ($mod -ne 0) { $t += "=" * (4 - $mod) }

    try {
        $bytes = [Convert]::FromBase64String($t)
        return [Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        throw "Base64 decode failed for Shadowsocks credential part."
    }
}

function Decode-SSUri {
    param([Parameter(Mandatory=$true)][string]$Uri)

    $raw = Remove-HiddenChars -s $Uri

    # Auto-prepend scheme if missing but looks like SS body
    if (-not ($raw -match "^\s*ss://")) {
        if ($raw -match "@.+:\d+") { $raw = "ss://$raw" }
        else { throw "Invalid URI: must start with ss://" }
    }

    $u = $raw.Substring($raw.IndexOf("ss://") + 5)

    $tag = "ss-out"
    if ($u -match "#") {
        $parts = $u.Split("#", 2)
        $u = $parts[0]
        $tag = [System.Uri]::UnescapeDataString($parts[1])
        if (-not $tag) { $tag = "ss-out" }
    }

    if ($u -match "\?") { $u = $u.Split("?",2)[0] }

    $server = $null
    $port = $null
    $method = $null
    $password = $null

    if ($u -match "@") {
        $cred, $hostport = $u.Split("@", 2)
        $decoded = Decode-Base64UrlUtf8 -s $cred
        $method, $password = $decoded.Split(":", 2)

        $hp = $hostport.Split(":", 2)
        $server = $hp[0]
        $port = [int]$hp[1]
    } else {
        $decoded = Decode-Base64UrlUtf8 -s $u
        $cred, $hostport = $decoded.Split("@", 2)
        $method, $password = $cred.Split(":", 2)

        $hp = $hostport.Split(":", 2)
        $server = $hp[0]
        $port = [int]$hp[1]
    }

    if ([string]::IsNullOrWhiteSpace($server) -or -not $port -or [string]::IsNullOrWhiteSpace($method) -or [string]::IsNullOrWhiteSpace($password)) {
        throw "Could not decode the Shadowsocks URI."
    }

    @{
        tag         = $tag
        server      = $server
        server_port = $port
        method      = $method
        password    = $password
    }
}

# --------------------------
# sing-box config generation
# --------------------------
function Write-SingBoxConfig {
    param([Parameter(Mandatory=$true)][hashtable]$ConfigObject)
    $json = $ConfigObject | ConvertTo-Json -Depth 60
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configPath, $json, $enc)
}

function New-SingBoxConfigObject {
    param(
        [Parameter(Mandatory=$true)][hashtable]$SS,
        [Parameter(Mandatory=$true)][string]$TunAddressCidr,
        [Parameter(Mandatory=$true)][int]$TunMtu,
        [Parameter(Mandatory=$true)][bool]$AutoRoute,
        [Parameter(Mandatory=$true)][bool]$AutoDetectInterface,
        [Parameter(Mandatory=$true)][bool]$StrictRoute,
        [Parameter(Mandatory=$false)][string]$DefaultInterfaceName,
        [Parameter(Mandatory=$true)][string]$DnsServer,
        [Parameter(Mandatory=$true)][string]$LogLevel
    )

    $routeRules = @(@{ ip_is_private = $true; outbound = "direct" })

    $routeObj = @{
        rules = $routeRules
        final = $SS.tag
    }

    if ($AutoDetectInterface) { $routeObj.auto_detect_interface = $true }
    elseif ($DefaultInterfaceName) { $routeObj.default_interface = $DefaultInterfaceName }

    @{
        log = @{
            level = $LogLevel
            output = "singbox.log"
            timestamp = $true
        }
        dns = @{
            servers = @(@{ address = $DnsServer })
        }
        route = $routeObj
        inbounds = @(
            @{
                type="tun"
                tag="tun-in"
                interface_name="singbox-tun0"
                address=@($TunAddressCidr)
                mtu=$TunMtu
                auto_route=$AutoRoute
                strict_route=$StrictRoute
                sniff=$true
            }
        )
        outbounds = @(
            @{
                type="shadowsocks"
                tag=$SS.tag
                server=$SS.server
                server_port=[int]$SS.server_port
                method=$SS.method
                password=$SS.password
            },
            @{ type="direct"; tag="direct" },
            @{ type="block";  tag="block"  }
        )
    }
}

# --------------------------
# sing-box process management
# --------------------------
$global:SingBoxProcess  = $null
$global:DesiredActive   = $false
$global:WatchdogTimer   = $null
$global:RestartCount    = 0
$global:NextRestartAt   = Get-Date
$script:WatchdogUpdateUi = $null

function Start-SingBox {
    if ($global:SingBoxProcess -and -not $global:SingBoxProcess.HasExited) { return }

    try { Reset-SingBoxNetworkState } catch { Write-AppLog "Pre-start cleanup failed: $($_.Exception.Message)" "WARN" }

    if (-not (Test-Path $singBoxExe)) { throw "sing-box.exe not found: $singBoxExe" }
    if (-not (Test-Path $wintunDll))  { throw "wintun.dll not found: $wintunDll" }
    if (-not (Test-Path $configPath)) { throw "Config not found. Generate it first." }

    Ensure-File -Path $stdoutPath
    Ensure-File -Path $stderrPath

    $args = @("run", "-c", ("`"" + $configPath + "`""))

    $p = Start-Process `
        -FilePath $singBoxExe `
        -ArgumentList $args `
        -WorkingDirectory $binDir `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError  $stderrPath

    $global:SingBoxProcess = $p
    Write-AppLog "sing-box started. PID=$($p.Id)" "INFO"
}

function Stop-SingBox {
    if ($global:SingBoxProcess -and -not $global:SingBoxProcess.HasExited) {
        try {
            Write-AppLog "Stopping sing-box PID=$($global:SingBoxProcess.Id)" "INFO"
            Stop-Process -Id $global:SingBoxProcess.Id -Force -ErrorAction SilentlyContinue
            try { $global:SingBoxProcess.WaitForExit(5000) | Out-Null } catch {}
        } catch {
            Write-AppLog "Stop error: $($_.Exception.Message)" "WARN"
        }
    }

    try { Reset-SingBoxNetworkState } catch { Write-AppLog "Post-stop cleanup failed: $($_.Exception.Message)" "WARN" }
    $global:SingBoxProcess = $null
}

function Start-Watchdog {
    param([Parameter(Mandatory=$true)][scriptblock]$UpdateUi)

    if ($global:WatchdogTimer) { return }
    $script:WatchdogUpdateUi = $UpdateUi

    $global:WatchdogTimer = New-Object System.Windows.Forms.Timer
    $global:WatchdogTimer.Interval = 1000

    $global:WatchdogTimer.Add_Tick({
        try { if ($script:WatchdogUpdateUi) { & $script:WatchdogUpdateUi } } catch {}

        if (-not $global:DesiredActive) { return }
        if (-not $global:SingBoxProcess) { return }

        if ($global:SingBoxProcess.HasExited) {
            $exit = $global:SingBoxProcess.ExitCode
            Write-AppLog "sing-box exited (code=$exit) while Active=true" "WARN"

            try { Reset-SingBoxNetworkState } catch { Write-AppLog "Watchdog cleanup failed: $($_.Exception.Message)" "WARN" }

            $now = Get-Date
            if ($now -lt $global:NextRestartAt) { return }

            $global:RestartCount++
            $delay = [Math]::Min(30, [Math]::Max(2, [int]([Math]::Pow(2, [Math]::Min(4, $global:RestartCount-1)))) )
            $global:NextRestartAt = $now.AddSeconds($delay)

            Write-AppLog "Watchdog restarting in $delay s (attempt $($global:RestartCount))" "INFO"
            try { Start-SingBox } catch { Write-AppLog "Watchdog restart failed: $($_.Exception.Message)" "ERROR" }
        } else {
            $global:RestartCount = 0
            $global:NextRestartAt = Get-Date
        }
    })

    $global:WatchdogTimer.Start()
}

function Stop-Watchdog {
    if ($global:WatchdogTimer) {
        try { $global:WatchdogTimer.Stop() } catch {}
        $global:WatchdogTimer = $null
    }
    $script:WatchdogUpdateUi = $null
}

# --------------------------
# UI (Resizable + dynamic layout)
# --------------------------
$COL_BG     = [System.Drawing.Color]::FromArgb(248, 249, 251)
$COL_PANEL  = [System.Drawing.Color]::White
$COL_TEXT   = [System.Drawing.Color]::FromArgb(33, 37, 41)
$COL_MUTED  = [System.Drawing.Color]::FromArgb(108, 117, 125)

$COL_ACCENT = [System.Drawing.Color]::FromArgb(13, 110, 253)
$COL_GO     = [System.Drawing.Color]::FromArgb(25, 135, 84)
$COL_STOP   = [System.Drawing.Color]::FromArgb(220, 53, 69)

$fontTitle  = New-Object System.Drawing.Font("Segoe UI Semibold", 14)
$fontUi     = New-Object System.Drawing.Font("Segoe UI", 9)
$fontMono   = New-Object System.Drawing.Font("Consolas", 9)

function Set-FlatButton($b, [System.Drawing.Color]$bg, [System.Drawing.Color]$fg) {
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $bg
    $b.ForeColor = $fg
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
}

function New-CardPanel([int]$x,[int]$y,[int]$w,[int]$h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x,$y)
    $p.Size = New-Object System.Drawing.Size($w,$h)
    $p.BackColor = $COL_PANEL
    $p.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $p
}

function New-Label([string]$Text,[int]$X,[int]$Y,[int]$W,[int]$H=18,[bool]$Bold=$false,[System.Drawing.Color]$Color=$COL_TEXT) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X,$Y)
    $l.Size = New-Object System.Drawing.Size($W,$H)
    $l.Font = if ($Bold) { New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold) } else { $fontUi }
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l
}

function New-TextBox([int]$X,[int]$Y,[int]$W,[int]$H=24,[string]$Text="") {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X,$Y)
    $t.Size = New-Object System.Drawing.Size($W,$H)
    $t.Font = $fontUi
    $t.Text = $Text
    $t
}

function New-CheckBox([string]$Text,[int]$X,[int]$Y,[int]$W,[bool]$Checked=$false) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Location = New-Object System.Drawing.Point($X,$Y)
    $c.Size = New-Object System.Drawing.Size($W,24)
    $c.Font = $fontUi
    $c.Checked = $Checked
    $c
}

function Get-NetAdapterNamesSafe {
    try { (Get-NetAdapter -ErrorAction Stop | Select-Object -ExpandProperty Name) } catch { @() }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "sing-box TUN Controller"
$form.StartPosition = "CenterScreen"
$form.BackColor = $COL_BG
$form.Font = $fontUi
$form.MinimumSize = New-Object System.Drawing.Size(820, 620)
$form.Size = New-Object System.Drawing.Size(980, 780)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = "sing-box TUN Controller"
$lblHeader.Font = $fontTitle
$lblHeader.Location = New-Object System.Drawing.Point(16, 12)
$lblHeader.Size = New-Object System.Drawing.Size(600, 32)
$lblHeader.ForeColor = $COL_TEXT
$lblHeader.BackColor = [System.Drawing.Color]::Transparent

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Download binaries, generate config, start/stop the TUN. Use Reset network if connectivity breaks."
$lblSub.Font = $fontUi
$lblSub.Location = New-Object System.Drawing.Point(18, 44)
$lblSub.Size = New-Object System.Drawing.Size(900, 18)
$lblSub.ForeColor = $COL_MUTED
$lblSub.BackColor = [System.Drawing.Color]::Transparent
$lblSub.Anchor = "Top,Left,Right"

$lblStatusTitle = New-Label -Text "Status" -X 0 -Y 0 -W 60 -Bold:$true
$lblStatusTitle.Location = New-Object System.Drawing.Point(0, 16)
$lblStatusTitle.Anchor = "Top,Right"

$lblStatusBadge = New-Object System.Windows.Forms.Label
$lblStatusBadge.Text = "Idle"
$lblStatusBadge.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblStatusBadge.TextAlign = "MiddleCenter"
$lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(233,236,239)
$lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(33,37,41)
$lblStatusBadge.Anchor = "Top,Right"

$cardConn = New-CardPanel -x 16 -y 72  -w 888 -h 160
$cardAct  = New-CardPanel -x 16 -y 242 -w 888 -h 92
$cardAdv  = New-CardPanel -x 16 -y 344 -w 888 -h 170
$cardLogs = New-CardPanel -x 16 -y 524 -w 888 -h 160

$cardConn.Anchor = "Top,Left,Right"
$cardAct.Anchor  = "Top,Left,Right"
$cardAdv.Anchor  = "Top,Left,Right"
$cardLogs.Anchor = "Top,Left,Right,Bottom"

$cardConn.Controls.Add((New-Label -Text "Connection" -X 12 -Y 10 -W 200 -Bold:$true))
$cardAct.Controls.Add((New-Label  -Text "Actions"    -X 12 -Y 10 -W 200 -Bold:$true))
$cardAdv.Controls.Add((New-Label  -Text "Advanced settings" -X 12 -Y 10 -W 250 -Bold:$true))
$cardLogs.Controls.Add((New-Label -Text "Logs"       -X 12 -Y 10 -W 120 -Bold:$true))

$cardConn.Controls.Add((New-Label -Text "Shadowsocks URI (ss://)" -X 12 -Y 42 -W 170 -Color $COL_MUTED))
$txtSS = New-TextBox -X 190 -Y 40 -W 680 -Text ""
$txtSS.Anchor = "Top,Left,Right"
$cardConn.Controls.Add($txtSS)

$cardConn.Controls.Add((New-Label -Text "DNS" -X 12 -Y 76 -W 60 -Color $COL_MUTED))
$txtDns = New-TextBox -X 190 -Y 74 -W 160 -Text "1.1.1.1"
$cardConn.Controls.Add($txtDns)

$cardConn.Controls.Add((New-Label -Text "TUN address (CIDR)" -X 12 -Y 110 -W 160 -Color $COL_MUTED))
$txtTunAddr = New-TextBox -X 190 -Y 108 -W 160 -Text "172.19.0.1/30"
$cardConn.Controls.Add($txtTunAddr)

$cardConn.Controls.Add((New-Label -Text "MTU" -X 370 -Y 110 -W 40 -Color $COL_MUTED))
$numMtu = New-Object System.Windows.Forms.NumericUpDown
$numMtu.Location = New-Object System.Drawing.Point(415, 108)
$numMtu.Size = New-Object System.Drawing.Size(90, 24)
$numMtu.Font = $fontUi
$numMtu.Minimum = 1200
$numMtu.Maximum = 9000
$numMtu.Value = 1500
$cardConn.Controls.Add($numMtu)

$cardConn.Controls.Add((New-Label -Text "Log level" -X 530 -Y 110 -W 70 -Color $COL_MUTED))
$cmbLog = New-Object System.Windows.Forms.ComboBox
$cmbLog.Location = New-Object System.Drawing.Point(610, 108)
$cmbLog.Size = New-Object System.Drawing.Size(260, 24)
$cmbLog.Font = $fontUi
$cmbLog.DropDownStyle = "DropDownList"
@("info","warn","error","debug","trace") | ForEach-Object { [void]$cmbLog.Items.Add($_) }
$cmbLog.SelectedItem = "info"
$cmbLog.Anchor = "Top,Right"
$cardConn.Controls.Add($cmbLog)

$btnDeps = New-Object System.Windows.Forms.Button
$btnDeps.Text = "Download / Update binaries"
$btnDeps.Size = New-Object System.Drawing.Size(210, 36)
$btnDeps.Font = $fontUi
Set-FlatButton $btnDeps $COL_ACCENT ([System.Drawing.Color]::White)

$btnGen = New-Object System.Windows.Forms.Button
$btnGen.Text = "Generate config"
$btnGen.Size = New-Object System.Drawing.Size(150, 36)
$btnGen.Font = $fontUi
Set-FlatButton $btnGen ([System.Drawing.Color]::FromArgb(108,117,125)) ([System.Drawing.Color]::White)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start"
$btnStart.Size = New-Object System.Drawing.Size(95, 36)
$btnStart.Font = $fontUi
Set-FlatButton $btnStart $COL_GO ([System.Drawing.Color]::White)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Size = New-Object System.Drawing.Size(95, 36)
$btnStop.Font = $fontUi
Set-FlatButton $btnStop $COL_STOP ([System.Drawing.Color]::White)

$btnResetNet = New-Object System.Windows.Forms.Button
$btnResetNet.Text = "Reset network"
$btnResetNet.Size = New-Object System.Drawing.Size(130, 36)
$btnResetNet.Font = $fontUi
Set-FlatButton $btnResetNet ([System.Drawing.Color]::FromArgb(255, 159, 67)) ([System.Drawing.Color]::FromArgb(33,37,41))

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = "Open folder"
$btnOpenFolder.Size = New-Object System.Drawing.Size(128, 36)
$btnOpenFolder.Font = $fontUi
Set-FlatButton $btnOpenFolder ([System.Drawing.Color]::FromArgb(13, 202, 240)) ([System.Drawing.Color]::FromArgb(33,37,41))

$cardAct.Controls.AddRange(@($btnDeps,$btnGen,$btnStart,$btnStop,$btnResetNet,$btnOpenFolder))

$chkShowAdvanced = New-CheckBox -Text "Show advanced settings" -X 12 -Y 40 -W 220 -Checked:$false
$chkAutoRoute = New-CheckBox -Text "auto_route (recommended)" -X 12 -Y 74 -W 220 -Checked:$true
$chkAutoDetect = New-CheckBox -Text "route.auto_detect_interface (recommended)" -X 250 -Y 74 -W 320 -Checked:$true
$chkStrictRoute = New-CheckBox -Text "strict_route (WARNING: can break internet if sing-box stops)" -X 12 -Y 104 -W 560 -Checked:$false

$lblIface = New-Label -Text "default_interface (only if auto_detect is OFF)" -X 12 -Y 136 -W 300 -Color $COL_MUTED
$cmbIface = New-Object System.Windows.Forms.ComboBox
$cmbIface.Location = New-Object System.Drawing.Point(330, 134)
$cmbIface.Size = New-Object System.Drawing.Size(320, 24)
$cmbIface.Font = $fontUi
$cmbIface.DropDownStyle = "DropDownList"
[void]$cmbIface.Items.Add("")
(Get-NetAdapterNamesSafe) | ForEach-Object { [void]$cmbIface.Items.Add($_) }
$cmbIface.SelectedIndex = 0

function Set-AdvancedVisibility([bool]$visible) {
    $chkAutoRoute.Visible = $visible
    $chkAutoDetect.Visible = $visible
    $chkStrictRoute.Visible = $visible
    $lblIface.Visible = $visible
    $cmbIface.Visible = $visible
    $cardAdv.Height = if ($visible) { 170 } else { 70 }
}
Set-AdvancedVisibility -visible:$false

$chkShowAdvanced.Add_CheckedChanged({
    Set-AdvancedVisibility -visible:([bool]$chkShowAdvanced.Checked)
    & $script:Layout
})

$chkAutoDetect.Add_CheckedChanged({ $cmbIface.Enabled = (-not [bool]$chkAutoDetect.Checked) })
$cmbIface.Enabled = (-not [bool]$chkAutoDetect.Checked)

$cardAdv.Controls.AddRange(@($chkShowAdvanced,$chkAutoRoute,$chkAutoDetect,$chkStrictRoute,$lblIface,$cmbIface))

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Font = $fontMono
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = "Vertical"
$txtOutput.ReadOnly = $true
$txtOutput.Anchor = "Top,Left,Right,Bottom"
$cardLogs.Controls.Add($txtOutput)

$btnCopyLog = New-Object System.Windows.Forms.Button
$btnCopyLog.Text = "Copy"
$btnCopyLog.Font = $fontUi
$btnCopyLog.Anchor = "Top,Right"

$btnOpenAppLog = New-Object System.Windows.Forms.Button
$btnOpenAppLog.Text = "Open app.log"
$btnOpenAppLog.Font = $fontUi
$btnOpenAppLog.Anchor = "Top,Right"

$btnOpenStdOut = New-Object System.Windows.Forms.Button
$btnOpenStdOut.Text = "Open stdout"
$btnOpenStdOut.Font = $fontUi
$btnOpenStdOut.Anchor = "Top,Right"

$btnOpenStdErr = New-Object System.Windows.Forms.Button
$btnOpenStdErr.Text = "Open stderr"
$btnOpenStdErr.Font = $fontUi
$btnOpenStdErr.Anchor = "Top,Right"

$btnClearUiLog = New-Object System.Windows.Forms.Button
$btnClearUiLog.Text = "Clear"
$btnClearUiLog.Font = $fontUi
$btnClearUiLog.Anchor = "Top,Right"

$cardLogs.Controls.AddRange(@($btnCopyLog,$btnOpenAppLog,$btnOpenStdOut,$btnOpenStdErr,$btnClearUiLog))

function Ui-Append([string]$Line) {
    $txtOutput.AppendText($Line + [Environment]::NewLine)
    $txtOutput.SelectionStart = $txtOutput.Text.Length
    $txtOutput.ScrollToCaret()
}

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.SizingGrip = $true
$stStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$stStatus.Text = "Idle"
$stPid = New-Object System.Windows.Forms.ToolStripStatusLabel
$stPid.Text = "PID: -"
$stUptime = New-Object System.Windows.Forms.ToolStripStatusLabel
$stUptime.Text = "Uptime: 00:00:00"
$statusStrip.Items.AddRange(@(
    $stStatus,
    (New-Object System.Windows.Forms.ToolStripStatusLabel -Property @{ Spring=$true }),
    $stPid,
    $stUptime
))

# --------------------------
# Dynamic layout (Resize)
# --------------------------
$script:Layout = {
    $pad = 16
    $w = $form.ClientSize.Width
    $h = $form.ClientSize.Height

    $lblStatusTitle.Location = New-Object System.Drawing.Point(($w - 210), 16)
    $lblStatusBadge.Location = New-Object System.Drawing.Point(($w - 145), 14)
    $lblStatusBadge.Size = New-Object System.Drawing.Size(130, 24)

    $cardWidth = $w - ($pad*2)
    $cardConn.Width = $cardWidth
    $cardAct.Width  = $cardWidth
    $cardAdv.Width  = $cardWidth
    $cardLogs.Width = $cardWidth

    $txtSS.Width = $cardConn.Width - 190 - 12
    $cmbLog.Location = New-Object System.Drawing.Point(($cardConn.Width - 12 - $cmbLog.Width), 108)

    $yBtn = 40
    $x = 12
    $gap = 10
    foreach ($b in @($btnDeps,$btnGen,$btnStart,$btnStop,$btnResetNet,$btnOpenFolder)) {
        $b.Location = New-Object System.Drawing.Point($x, $yBtn)
        $x += $b.Width + $gap
    }

    $cardConn.Location = New-Object System.Drawing.Point($pad, 72)
    $cardAct.Location  = New-Object System.Drawing.Point($pad, ($cardConn.Bottom + 10))
    $cardAdv.Location  = New-Object System.Drawing.Point($pad, ($cardAct.Bottom + 10))
    $cardLogs.Location = New-Object System.Drawing.Point($pad, ($cardAdv.Bottom + 10))

    $statusH = $statusStrip.Height
    $bottomLimit = $h - $statusH - 8
    $cardLogs.Height = [Math]::Max(140, ($bottomLimit - $cardLogs.Top))

    $rightColW = 202
    $btnW = 96
    $btnH = 30

    $txtOutput.Location = New-Object System.Drawing.Point(12, 40)
    $txtOutput.Size = New-Object System.Drawing.Size(($cardLogs.Width - 12 - 12 - $rightColW), ($cardLogs.Height - 52))

    $rx = ($txtOutput.Right + 10)
    $btnCopyLog.Location    = New-Object System.Drawing.Point($rx, 40);  $btnCopyLog.Size    = New-Object System.Drawing.Size($btnW,$btnH)
    $btnOpenAppLog.Location = New-Object System.Drawing.Point(($rx+$btnW+10), 40); $btnOpenAppLog.Size = New-Object System.Drawing.Size($btnW,$btnH)

    $btnOpenStdOut.Location = New-Object System.Drawing.Point($rx, 78);  $btnOpenStdOut.Size  = New-Object System.Drawing.Size($btnW,$btnH)
    $btnOpenStdErr.Location = New-Object System.Drawing.Point(($rx+$btnW+10), 78); $btnOpenStdErr.Size  = New-Object System.Drawing.Size($btnW,$btnH)

    $btnClearUiLog.Location = New-Object System.Drawing.Point($rx, 116); $btnClearUiLog.Size  = New-Object System.Drawing.Size($rightColW,$btnH)
}

$form.Add_Resize({ & $script:Layout })

# --------------------------
# UX state helpers
# --------------------------
$script:StartedAt = $null
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 1000

function Set-StatusBadge([string]$text) {
    $lblStatusBadge.Text = $text
    $stStatus.Text = $text

    switch ($text) {
        "Running" {
            $lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(209, 231, 221)
            $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(15, 81, 50)
        }
        "Starting" {
            $lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(207, 226, 255)
            $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(8, 66, 152)
        }
        "Stopping" {
            $lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(255, 243, 205)
            $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(102, 77, 3)
        }
        "Crashed" {
            $lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(248, 215, 218)
            $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(132, 32, 41)
        }
        Default {
            $lblStatusBadge.BackColor = [System.Drawing.Color]::FromArgb(233, 236, 239)
            $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
        }
    }
}

function Update-ButtonsState {
    $hasConfig = Test-Path $configPath
    $isRunning = ($global:SingBoxProcess -and -not $global:SingBoxProcess.HasExited)
    $btnStart.Enabled = $hasConfig -and (-not $isRunning)
    $btnStop.Enabled  = $isRunning
}

function Update-UiState {
    $isRunning = ($global:SingBoxProcess -and -not $global:SingBoxProcess.HasExited)

    if ($global:DesiredActive) {
        if ($isRunning) { Set-StatusBadge "Running" }
        elseif ($global:SingBoxProcess -and $global:SingBoxProcess.HasExited) { Set-StatusBadge "Crashed" }
        else { Set-StatusBadge "Starting" }
    } else {
        if ($isRunning) { Set-StatusBadge "Stopping" }
        else { Set-StatusBadge "Idle" }
    }

    if ($isRunning -and $global:SingBoxProcess) {
        $stPid.Text = "PID: $($global:SingBoxProcess.Id)"
    } else {
        $stPid.Text = "PID: -"
    }

    if ($script:StartedAt -and $isRunning) {
        $span = (Get-Date) - $script:StartedAt
        $stUptime.Text = ("Uptime: {0:00}:{1:00}:{2:00}" -f $span.Hours, $span.Minutes, $span.Seconds)
    } else {
        $stUptime.Text = "Uptime: 00:00:00"
    }

    Update-ButtonsState
}

$uiTimer.Add_Tick({ Update-UiState })
$uiTimer.Start()

function Validate-InputsOrThrow {
    $ssText = Remove-HiddenChars -s $txtSS.Text
    if (-not $ssText) { throw "Please paste a valid ss:// URI." }

    if (-not ($ssText -match "^\s*ss://") -and -not ($ssText -match "@.+:\d+")) {
        throw "The URI must start with 'ss://' (or look like a valid SS body containing '@host:port')."
    }

    $dns = ($txtDns.Text.Trim())
    if (-not $dns) { throw "DNS cannot be empty." }

    $tun = ($txtTunAddr.Text.Trim())
    if (-not $tun -or ($tun -notmatch "^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$")) {
        throw "TUN address must be in CIDR form (example: 172.19.0.1/30)."
    }
}

# --------------------------
# Button handlers
# --------------------------
$btnDeps.Add_Click({
    try {
        Ui-Append "[$(New-Timestamp)] Downloading dependencies..."
        Ensure-Dependencies
        Ui-Append "[$(New-Timestamp)] OK: Dependencies are ready in $binDir"
        Write-AppLog "Dependencies updated" "INFO"
    } catch {
        $msg = $_.Exception.Message
        Ui-Append "[$(New-Timestamp)] ERROR: $msg"
        Write-AppLog "Dependencies error: $msg" "ERROR"
        [System.Windows.Forms.MessageBox]::Show($msg, "Dependencies error", "OK", "Error") | Out-Null
    } finally { Update-UiState }
})

$btnGen.Add_Click({
    try {
        Validate-InputsOrThrow
        Ensure-Dependencies

        $ssText = Remove-HiddenChars -s $txtSS.Text
        $ss = Decode-SSUri -Uri $ssText

        $autoDetect = [bool]$chkAutoDetect.Checked
        $ifaceName = ""
        if (-not $autoDetect) { $ifaceName = [string]$cmbIface.SelectedItem }

        $cfgObj = New-SingBoxConfigObject `
            -SS $ss `
            -TunAddressCidr ($txtTunAddr.Text.Trim()) `
            -TunMtu ([int]$numMtu.Value) `
            -AutoRoute ([bool]$chkAutoRoute.Checked) `
            -AutoDetectInterface $autoDetect `
            -StrictRoute ([bool]$chkStrictRoute.Checked) `
            -DefaultInterfaceName $ifaceName `
            -DnsServer ($txtDns.Text.Trim()) `
            -LogLevel ([string]$cmbLog.SelectedItem)

        Write-SingBoxConfig -ConfigObject $cfgObj
        Ui-Append "[$(New-Timestamp)] Config written: $configPath (UTF-8 no BOM)"
        Write-AppLog "Config written: $configPath" "INFO"
    } catch {
        $msg = $_.Exception.Message
        Ui-Append "[$(New-Timestamp)] ERROR: $msg"
        Write-AppLog "Config error: $msg" "ERROR"
        [System.Windows.Forms.MessageBox]::Show($msg, "Config error", "OK", "Error") | Out-Null
    } finally { Update-UiState }
})

$btnStart.Add_Click({
    try {
        if (-not (Test-IsAdmin)) {
            $msg = "Please start PowerShell as Administrator (required for TUN and route operations)."
            Ui-Append "[$(New-Timestamp)] ERROR: $msg"
            Write-AppLog $msg "ERROR"
            [System.Windows.Forms.MessageBox]::Show($msg, "Administrator required", "OK", "Warning") | Out-Null
            return
        }

        Ensure-Dependencies
        if (-not (Test-Path $configPath)) { throw "Config not found. Click 'Generate config' first." }

        $global:DesiredActive = $true
        Set-StatusBadge "Starting"
        Update-ButtonsState

        Start-SingBox
        $script:StartedAt = Get-Date

        Ui-Append "[$(New-Timestamp)] Start requested."
        Write-AppLog "Start requested" "INFO"

        Start-Watchdog -UpdateUi { Update-UiState }
    } catch {
        $msg = $_.Exception.Message
        Ui-Append "[$(New-Timestamp)] ERROR: $msg"
        Write-AppLog "Start error: $msg" "ERROR"
        [System.Windows.Forms.MessageBox]::Show($msg, "Start error", "OK", "Error") | Out-Null
    } finally { Update-UiState }
})

$btnStop.Add_Click({
    try {
        if ($global:SingBoxProcess -and -not $global:SingBoxProcess.HasExited) {
            $res = [System.Windows.Forms.MessageBox]::Show(
                "Stop sing-box now?",
                "Confirm",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($res -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }

        $global:DesiredActive = $false
        Set-StatusBadge "Stopping"
        Update-ButtonsState

        Stop-SingBox
        $script:StartedAt = $null

        Ui-Append "[$(New-Timestamp)] Stop requested."
        Write-AppLog "Stop requested" "INFO"
    } catch {
        $msg = $_.Exception.Message
        Ui-Append "[$(New-Timestamp)] ERROR: $msg"
        Write-AppLog "Stop error: $msg" "ERROR"
        [System.Windows.Forms.MessageBox]::Show($msg, "Stop error", "OK", "Error") | Out-Null
    } finally { Update-UiState }
})

$btnResetNet.Add_Click({
    try {
        if (-not (Test-IsAdmin)) { throw "Administrator privileges are required." }

        $res = [System.Windows.Forms.MessageBox]::Show(
            "This will remove singbox-tun* routes and adapters. Continue?",
            "Confirm network reset",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($res -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Ui-Append "[$(New-Timestamp)] Resetting network state (singbox-tun*)..."
        Reset-SingBoxNetworkState
        Ui-Append "[$(New-Timestamp)] OK: network state cleaned."
        Write-AppLog "Network reset executed from GUI" "INFO"
    } catch {
        $msg = $_.Exception.Message
        Ui-Append "[$(New-Timestamp)] ERROR: $msg"
        Write-AppLog "Network reset error: $msg" "ERROR"
        [System.Windows.Forms.MessageBox]::Show($msg, "Network reset error", "OK", "Error") | Out-Null
    } finally { Update-UiState }
})

$btnOpenFolder.Add_Click({ try { Start-Process explorer.exe $scriptDir | Out-Null } catch {} })

$btnCopyLog.Add_Click({
    try {
        [System.Windows.Forms.Clipboard]::SetText($txtOutput.Text)
        Ui-Append "[$(New-Timestamp)] Copied log to clipboard."
    } catch {}
})
$btnOpenAppLog.Add_Click({ try { Ensure-File -Path $appLogPath; Start-Process notepad.exe $appLogPath | Out-Null } catch {} })
$btnOpenStdOut.Add_Click({ try { Ensure-File -Path $stdoutPath; Start-Process notepad.exe $stdoutPath | Out-Null } catch {} })
$btnOpenStdErr.Add_Click({ try { Ensure-File -Path $stderrPath; Start-Process notepad.exe $stderrPath | Out-Null } catch {} })
$btnClearUiLog.Add_Click({ $txtOutput.Clear() })

$form.Add_FormClosing({
    try {
        $global:DesiredActive = $false
        Stop-Watchdog
        Stop-SingBox
    } catch {}
})

$form.Controls.AddRange(@(
    $lblHeader,$lblSub,$lblStatusTitle,$lblStatusBadge,
    $cardConn,$cardAct,$cardAdv,$cardLogs,
    $statusStrip
))

# Initial layout + initial log
& $script:Layout
Ui-Append "[$(New-Timestamp)] Ready."
Ui-Append "Tip: Keep 'strict_route' OFF unless you really need it."
Ui-Append "Logs: app.log, singbox.stdout.log, singbox.stderr.log"
Ui-Append "Binaries folder: $binDir"

Update-UiState
[void]$form.ShowDialog()
