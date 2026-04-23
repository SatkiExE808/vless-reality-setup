<div align="center">

# ⚡ sing-box Proxy Manager

### One-command, interactive installer for [sing-box](https://github.com/SagerNet/sing-box) on any VPS

**VLESS Reality · Hysteria2 · VMess+WS · TUIC v5 · SOCKS5** — pick any combination.

[![License](https://img.shields.io/github/license/SatkiExE808/vless-reality-setup?style=for-the-badge&color=blue)](LICENSE)
[![Stars](https://img.shields.io/github/stars/SatkiExE808/vless-reality-setup?style=for-the-badge&color=yellow)](https://github.com/SatkiExE808/vless-reality-setup/stargazers)
[![Platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu-orange?style=for-the-badge)]()
[![Arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-green?style=for-the-badge)]()
[![Shell](https://img.shields.io/badge/shell-bash-lightgrey?style=for-the-badge&logo=gnubash&logoColor=white)]()

```
╔══════════════════════════════════════════════════╗
║       V P S   T O O L B O X                      ║
╠══════════════════════════════════════════════════╣
║  Status  ● running      Version  1.13.9          ║
╚══════════════════════════════════════════════════╝
```

</div>

---

## 🚀 Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/SatkiExE808/vless-reality-setup/main/setup.sh)
```

> Requires **root**. After the first run, type `sb` anywhere to reopen the manager.

---

## ✨ Features

| | |
|---|---|
| 🎛️ **Interactive Menu** | Full TUI — install, manage, update, uninstall |
| 📦 **Auto-Install** | Fetches the latest `sing-box` release binary |
| 🔀 **Mix & Match** | Add or remove any protocol at any time |
| 📱 **QR Codes** | Ready-to-scan QR for mobile clients |
| ⚡ **BBR Toggle** | One-click BBR congestion control |
| 🛠️ **VPS Toolbox** | IP info · Speed test · DNS · Fail2ban · Updates |
| 🐚 **`sb` Shortcut** | Re-open the manager from any directory |
| 🖥️ **Multi-Arch** | Supports `amd64` and `arm64` |
| 🐧 **Wide Compat** | Debian 11/12 · Ubuntu 20.04+ |

---

## 📡 Supported Protocols

<table>
<tr>
<th>Protocol</th>
<th>Transport</th>
<th>Speed</th>
<th>Stealth</th>
<th>Best For</th>
</tr>
<tr>
<td>🔐 <b>VLESS Reality</b></td>
<td>TCP</td>
<td>⚡⚡⚡</td>
<td>🥇 Highest</td>
<td>Strict censorship</td>
</tr>
<tr>
<td>🚀 <b>Hysteria2</b></td>
<td>UDP (QUIC)</td>
<td>⚡⚡⚡⚡⚡</td>
<td>🥈 Medium</td>
<td>High-latency links</td>
</tr>
<tr>
<td>🌐 <b>VMess + WS</b></td>
<td>TCP</td>
<td>⚡⚡</td>
<td>🥉 Low (needs CDN)</td>
<td>Behind Cloudflare</td>
</tr>
<tr>
<td>🛸 <b>TUIC v5</b></td>
<td>UDP (QUIC)</td>
<td>⚡⚡⚡⚡</td>
<td>🥈 Medium</td>
<td>Low-latency QUIC</td>
</tr>
<tr>
<td>📦 <b>SOCKS5</b></td>
<td>TCP</td>
<td>⚡⚡⚡</td>
<td>— None</td>
<td>Simple proxy</td>
</tr>
</table>

---

## 🖼️ Menu Preview

<details open>
<summary><b>📋 Main Menu</b></summary>

```
╔══════════════════════════════════════════════════╗
║       V P S   T O O L B O X                      ║
╠══════════════════════════════════════════════════╣
║  Status  ● running      Version  1.13.9          ║
╚══════════════════════════════════════════════════╝

  ──── Proxy ────────────────────────────────────────
    1  ›  Show Config & Links
    2  ›  Add Protocol
    3  ›  Remove Protocol

  ──── Service ──────────────────────────────────────
    4  ›  Restart Service
    5  ›  Stop / Start Service
    6  ›  View Logs

  ──── System ───────────────────────────────────────
    7  ›  Update sing-box
    8  ›  BBR Enable / Disable
    9  ›  VPS Toolbox
   10  ›  Reinstall
   11  ›  Uninstall

    0  ›  Exit
```

</details>

<details>
<summary><b>🧰 VPS Toolbox</b></summary>

```
  ──── Network ──────────────────────────────────────
    1  ›  Check IP Info
    2  ›  Speed Test
    3  ›  Check DNS
    4  ›  Change DNS

  ──── Diagnostics ──────────────────────────────────
    5  ›  Node Quality Check

  ──── Maintenance ──────────────────────────────────
    6  ›  System Update
    7  ›  Fail2Ban
```

</details>

<details>
<summary><b>➕ Add Protocol</b></summary>

```
  ✓  VLESS Reality
  ✓  Hysteria2

  ──────────────────────────────────────────────────
    1  ›  VMess + WebSocket      TCP · compatible
    2  ›  TUIC                   UDP · fast · QUIC
    3  ›  SOCKS5                 TCP · simple
  ──────────────────────────────────────────────────
    0  ›  Back
```

</details>

---

## 🔐 Protocol Details

### 🔐 VLESS Reality
Uses the real TLS certificate of `www.microsoft.com` — traffic is **indistinguishable from normal HTTPS**. The most censorship-resistant option available today.

| Field | Value |
|---|---|
| **Flow** | `xtls-rprx-vision` |
| **SNI** | `www.microsoft.com` |
| **Fingerprint** | `chrome` |
| **Transport** | TCP |

### 🚀 Hysteria2
QUIC-based protocol with self-signed TLS. Ideal for **high-bandwidth** or **high-latency** connections — outperforms TCP-based protocols on lossy networks.

### 🌐 VMess + WebSocket
VMess over WebSocket transport. No TLS — **best used behind a CDN** (e.g. Cloudflare). Widely compatible with nearly all clients.

| Field | Value |
|---|---|
| **Network** | `ws` |
| **AlterId** | `0` |
| **TLS** | none |

### 🛸 TUIC v5
QUIC-based with BBR congestion control and self-signed TLS. **Low latency**, similar to Hysteria2 but with a different congestion model.

| Field | Value |
|---|---|
| **Congestion** | `bbr` |
| **ALPN** | `h3` |
| **TLS** | self-signed (`insecure=1`) |

### 📦 SOCKS5
Simple TCP proxy built into sing-box. Optional username/password authentication. No extra software needed — works in any browser or app.

---

## ⚡ BBR Congestion Control

Option **8** in the management menu toggles BBR system-wide.

- ✅ **Enable** — loads the `tcp_bbr` kernel module, sets `fq` qdisc, writes `/etc/sysctl.d/99-bbr.conf` for persistence.
- ❌ **Disable** — reverts to `cubic` + `pfifo_fast`, removes the persistent config.

> 💡 BBR typically gives **2×–10× throughput** on lossy connections.

---

## 📱 Client Setup

<table>
<tr>
<td width="50%" valign="top">

### 💻 Windows — v2rayN

**VLESS Reality / VMess**
1. Copy the import link from output
2. `Servers` → `Import bulk URL from clipboard`
3. Right-click → `Set as active server`
4. Enable system proxy

> ⚠️ **Flow** must be `xtls-rprx-vision` for Reality.

</td>
<td width="50%" valign="top">

### 📱 Android — NekoBox / v2rayNG

1. Scan the QR code printed after installation
2. Or paste the import link manually
3. Enable the VPN

**Recommended clients:**
- [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid)
- [Hiddify](https://hiddify.com/)
- [v2rayNG](https://github.com/2dust/v2rayNG)

</td>
</tr>
<tr>
<td valign="top">

### 🍎 iOS — Shadowrocket / Streisand

1. Copy import link → app auto-detects
2. Or scan QR code
3. Toggle the profile on

</td>
<td valign="top">

### 🌐 SOCKS5 — Any Client

Use the displayed IP, port, and credentials directly in your browser or app's proxy settings.

</td>
</tr>
</table>

---

## 🛠️ Service Management

```bash
sb                               # Open manager
systemctl status sing-box        # Check status
systemctl restart sing-box       # Restart
journalctl -u sing-box -f        # Live logs
systemctl stop sing-box          # Stop
```

---

## 📁 Installation Paths

| Path | Purpose |
|---|---|
| `/usr/local/bin/sing-box` | sing-box binary |
| `/usr/local/bin/sb` | Quick-access shortcut |
| `/etc/sing-box/config.json` | Active config |
| `/etc/sing-box/.info` | Saved credentials (mode 600) |
| `/etc/sing-box/cert.pem` | TLS cert (Hysteria2 / TUIC) |
| `/etc/sysctl.d/99-bbr.conf` | BBR persistent config |
| `/etc/systemd/system/sing-box.service` | systemd service |

---

## 📋 Requirements

- 🐧 **OS:** Debian 11+ or Ubuntu 20.04+
- 🔑 **Privileges:** root
- 📦 **Pre-installed:** `curl`, `openssl` (standard on all VPS images)

---

## ❓ FAQ

<details>
<summary><b>Why does Reality use `www.microsoft.com` as SNI?</b></summary>

Because it's one of the most visited HTTPS domains on the internet — blocking it would break Windows Update, Outlook, Teams, Office 365, and much more. This makes the traffic **statistically indistinguishable** from legitimate traffic.

</details>

<details>
<summary><b>Can I run multiple protocols on the same VPS?</b></summary>

Yes. Pick option `6 - All protocols` during install, or add them individually later via the `Add Protocol` menu. Each protocol runs on its own port.

</details>

<details>
<summary><b>Do I need to open firewall ports manually?</b></summary>

Depends on your VPS provider. Most cheap VPSs have no firewall by default. If you use `ufw` or `iptables`, you'll need to open the ports for each enabled protocol (default: 443, 8443, 8080, 8853, 1080).

</details>

<details>
<summary><b>How do I update sing-box?</b></summary>

Open the manager (`sb`) → option `7 — Update sing-box`. Auto-detects the latest release from GitHub.

</details>

<details>
<summary><b>What if sing-box fails to start after install?</b></summary>

Check logs:
```bash
journalctl -u sing-box -n 50
```
Most common causes: port conflict (something else already listening) or cert/key mismatch.

</details>

---

## 📄 License

[MIT](LICENSE) — free to use, fork, and modify.

---

<div align="center">

**⭐ If this helped you, consider starring the repo!**

Made with ❤️ for the self-hosted community

</div>
