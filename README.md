# sing-box TUN Controller (PowerShell GUI)

**Shadowsocks “VPN-like” connector for Windows**
![Sing-box TUN Controller](https://raw.githubusercontent.com/michele-tn/sing-box-TUN-Controller-PowerShell-GUI-Shadowsocks-VPN-like-Connector-for-Windows/3ad3bd2e3e07b09ef71a56e329c6d522d42f1d4f/Sin-box%20TUN%20Controller.jpg)



A small **PowerShell + WinForms** desktop GUI that automates a **TUN-mode** connection using **sing-box** and your **personal Shadowsocks server**, giving a *VPN-like* experience on Windows.

> **What you get:** a one-click Start/Stop experience that downloads required binaries, generates a `sing-box.json` config from an `ss://` URI, runs sing-box in the background, and provides cleanup tools if Windows networking gets “stuck”.

---

## Features

- **GUI (WinForms), resizable layout**
- **Download / update** the latest **sing-box** for Windows (GitHub Releases)
- **Download / update** **Wintun** from the official site and **verify SHA-256**
- **Robust `ss://` parsing**
  - Accepts both common URI forms (base64 userinfo or fully base64-encoded)
  - Auto-prepends `ss://` when input looks like `...@host:port`
  - Strips hidden Unicode characters (BOM / zero-width)
- **Generate config** (`sing-box.json`) for:
  - TUN inbound (`interface_name: singbox-tun0`)
  - DNS server selection (default `1.1.1.1`)
  - Routing rule: **private IP ranges go direct**, everything else via Shadowsocks
- **Start / Stop** sing-box with:
  - stdout/stderr redirection to log files
  - **watchdog** (auto-restart with exponential backoff)
  - **network cleanup** (routes + lingering adapters)
- Buttons to **Reset network**, **Open folder**, and open/copy logs

---

## Requirements

- **Windows 10/11**
- **PowerShell 5.1** (Windows PowerShell) or **PowerShell 7+**
- **Administrator privileges** *(required for TUN adapter and route changes)*
- Internet access to download dependencies (sing-box + Wintun)

---

## Quick start

1. **Open PowerShell as Administrator**
2. Run the script from its folder:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\SingBoxTunGui.ps1
   ```
3. In the GUI:
   1. Click **Download / Update binaries**
   2. Paste your **Shadowsocks URI** into **“Shadowsocks URI (ss://)”**
   3. (Optional) change:
      - **DNS** (default `1.1.1.1`)
      - **TUN address (CIDR)** (default `172.19.0.1/30`)
      - **MTU** (default `1500`)
      - **Log level** (`info`, `warn`, `error`, `debug`, `trace`)
   4. Click **Generate config**
   5. Click **Start**

To stop tunneling, click **Stop**.

If connectivity breaks (e.g., after a crash), click **Stop** and then **Reset network**.

---

## Supported Shadowsocks URI formats

The GUI accepts standard Shadowsocks URIs, for example:

- Base64 **userinfo**:
  ```
  ss://<base64(method:password)>@host:port#MyTag
  ```
- Fully base64 encoded:
  ```
  ss://<base64(method:password@host:port)>#MyTag
  ```

Notes:
- Anything after `#` becomes the **outbound tag** in sing-box (fallback: `ss-out`).
- Query string parameters after `?` are ignored by this script.

---

## What the script generates (configuration overview)

The generated `sing-box.json` includes:

### Inbound (TUN)
- `type: "tun"`
- `interface_name: "singbox-tun0"`
- `address: ["<CIDR>"]`
- `mtu: <MTU>`
- `auto_route: <true/false>`
- `strict_route: <true/false>`
- `sniff: true`

### Outbounds
- `type: "shadowsocks"` from your `ss://` URI (method, password, host, port)
- `direct`
- `block`

### Routing
- Rule: `ip_is_private = true` → `direct`
- `final` outbound → your Shadowsocks tag

### DNS
- `servers: [{ address: "<DNS>" }]`

### Logging
- `singbox.log` with timestamps (level controlled by the GUI)

---

## Advanced settings (GUI)

Enable **“Show advanced settings”** to control:

- **`auto_route` (recommended)**  
  Lets sing-box automatically add routes for tunneling traffic.

- **`route.auto_detect_interface` (recommended)**  
  Lets sing-box detect the default outbound interface automatically.

- **`strict_route` (⚠️ WARNING)**  
  More aggressive routing behavior. If sing-box stops unexpectedly, it can temporarily break internet access until routes/adapters are cleaned up. Use only if you know why you need it.

- **`default_interface` (only if auto-detect is OFF)**  
  Choose a specific Windows interface name from the dropdown.

---

## Files & folders created

The script uses its own folder (same directory as `SingBoxTunGui.ps1`):

- `bin/`
  - `sing-box.exe`
  - `wintun.dll`
- `sing-box.json` — generated configuration
- `app.log` — GUI/script log (downloads, errors, watchdog notes)
- `singbox.stdout.log` — sing-box standard output
- `singbox.stderr.log` — sing-box standard error
- `singbox.log` — log file produced by sing-box (configured in JSON)

---

## Networking cleanup / “Reset network” (what it does)

The **Reset network** button performs cleanup intended to recover from partial TUN/routing state:

- Removes routes bound to interfaces matching `singbox-tun*`
- Disables and attempts to remove lingering `singbox-tun*` adapters  
  (uses `Remove-PnpDevice` when available, otherwise falls back to `pnputil.exe`)

Admin rights are required.

---

## Troubleshooting

### Must run as Administrator / routes fail
Re-launch PowerShell **as Administrator**, then run the script again.

### sing-box starts but no internet
1. Click **Stop**
2. Click **Reset network**
3. Click **Start**
4. If you enabled **strict_route**, try turning it off.

### DNS issues
Try a different resolver and regenerate config (e.g., `9.9.9.9` or your internal DNS).

### MTU issues (slow sites / broken downloads)
Lower MTU (e.g., `1400–1480`), regenerate config, restart.

### Corporate proxy / downloads fail
The downloader uses **HttpClient** with the **system proxy** and default credentials where possible, but some environments still block GitHub or Wintun downloads. In that case:
- Download `sing-box.exe` and `wintun.dll` manually into `bin/`, then retry.

---

## Security notes

- Your Shadowsocks **password is written into `sing-box.json` in plain text** (required by sing-box).
- Protect the folder with appropriate NTFS permissions.
- Avoid sharing `sing-box.json` and logs publicly.

---

## ⬇️ Download

👉 **[Scarica sing-box TUN Controller](https://github.com/michele-tn/sing-box-TUN-Controller-PowerShell-GUI-Shadowsocks-VPN-like-Connector-for-Windows/blob/main/sing-box%20TUN%20Controller.7z)**

### 🔐 SHA-512 File Hash

```text
b84e2ca49e05415835aff445d2f709160480e6ed5dd4ab566b6b5bd57818f5f8afd403dae67c778a7204cd023fffdc19485b62b6863ced2463f594d20d4eb45b
```
---

## Disclaimer

This script modifies network configuration (TUN adapters and routes). Use at your own risk.  
If anything gets stuck, use **Stop** and **Reset network**, then review the logs.

---

## Credits

- **sing-box** (core proxy engine) — SagerNet/sing-box
- **Wintun** (TUN driver for Windows)
- 


#  〽️ SingBoxTunGui – Minimal PowerShell Script Fixes - UPDATE `04/02/2026 15:18:37`

<img width="651" height="309" alt="image" src="https://github.com/user-attachments/assets/cb79dff0-b59f-4cc2-8b09-eb4591eb1b55" />

This document describes the **minimal and safe modifications** applied to `SingBoxTunGui.ps1` to ensure reliable execution across different PowerShell hosts and correct handling of relative paths.

These changes do **not** alter the script logic or behavior, but only improve compatibility and stability.

---

## 1. Explicitly load `System.Net.Http`

Some PowerShell environments (especially when running `powershell.exe` instead of `pwsh`) do not automatically load the `System.Net.Http` assembly.  
This can result in runtime errors such as:

> `Unable to find type [System.Net.Http.HttpClientHandler]`

To prevent this, the following code is added **immediately after the existing `Add-Type` statements**:

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Ensure System.Net.Http is available (fixes missing HttpClientHandler on some hosts)
try {
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
} catch {
    throw "Unable to load System.Net.Http. Use pwsh (PowerShell 7) or ensure Windows PowerShell 5.1 + .NET Framework 4.5+ is installed. Details: $($_.Exception.Message)"
}
```

This guarantees that `HttpClientHandler` and other HTTP-related types are available before being used by the script.

---

## 2. Force the working directory to the script location

PowerShell resolves relative paths based on the current working directory, not on the script’s location.  
When the script is launched from a different directory, this can cause paths to resolve incorrectly.

To avoid this issue, the script now explicitly sets the working directory to its own folder:

```powershell
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $scriptDir
```

This ensures that all relative paths (binaries, configuration files, logs, downloads, etc.) are resolved correctly regardless of how the script is launched.

---

## How to use

1. Replace your existing `SingBoxTunGui.ps1` with the fixed version  
   (or rename the downloaded file to `SingBoxTunGui.ps1`).

2. Run the script using PowerShell 7 (recommended):

```cmd
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\Users\<Username>\Downloads\sing-box TUN Controller\SingBoxTunGui.ps1"
```

Running the script with `pwsh` ensures full .NET compatibility and avoids legacy limitations of Windows PowerShell.

