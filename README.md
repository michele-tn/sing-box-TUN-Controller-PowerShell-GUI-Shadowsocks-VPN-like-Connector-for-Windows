# sing-box TUN Controller (PowerShell GUI)
**Shadowsocks “VPN-like” connector for Windows**

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

## Disclaimer

This script modifies network configuration (TUN adapters and routes). Use at your own risk.  
If anything gets stuck, use **Stop** and **Reset network**, then review the logs.

---

## Credits

- **sing-box** (core proxy engine) — SagerNet/sing-box
- **Wintun** (TUN driver for Windows)
