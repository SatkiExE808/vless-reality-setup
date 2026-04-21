# sing-box Proxy Manager

A clean, interactive installer and manager for [sing-box](https://github.com/SagerNet/sing-box) — supports **VLESS Reality**, **Hysteria2**, **SOCKS5**, **VMess+WebSocket**, and **TUIC v5** in any combination.

- Interactive menu — install, manage, update, uninstall
- Auto-installs latest sing-box binary
- Mix and match protocols — add or remove any protocol at any time
- QR code output for mobile clients
- BBR congestion control toggle (enable / disable)
- `sb` shortcut installed automatically for quick access
- Supports `amd64` and `arm64`
- Tested on Debian 11/12 and Ubuntu 20.04+

---

## Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/SatkiExE808/vless-reality-setup/main/setup.sh)
```

> Requires root. After the first run, type `sb` anywhere to reopen the manager.

---

## Protocol Menu

```
  1. VLESS Reality          (TCP · most secure)
  2. Hysteria2              (UDP · fast)
  3. SOCKS5                 (TCP · simple)
  4. VMess + WebSocket      (TCP · compatible)
  5. TUIC                   (UDP · fast · QUIC)
  6. All protocols
```

---

## Management Menu

```
╔══════════════════════════════════════════════╗
║  sing-box Proxy Manager                      ║
║  github.com/SatkiExE808/vless-reality-setup  ║
╚══════════════════════════════════════════════╝

  Status : ● running   Version : 1.13.9

  1. Show Config & Links
  2. Add Protocol
  3. Remove Protocol
  4. Restart Service
  5. Stop / Start Service
  6. View Logs
  7. Update sing-box
  8. BBR Enable / Disable
  9. Reinstall
  10. Uninstall

  0. Exit
```

---

## Protocols

### VLESS Reality
Uses the real TLS certificate of `www.microsoft.com` — traffic is indistinguishable from normal HTTPS. Most censorship-resistant option.

| Field | Value |
|---|---|
| Flow | `xtls-rprx-vision` |
| SNI | `www.microsoft.com` |
| Fingerprint | `chrome` |
| Transport | TCP |

### Hysteria2
QUIC-based protocol with self-signed TLS. Ideal for high-bandwidth or high-latency connections.

### SOCKS5
Simple TCP proxy built into sing-box. Optional username/password authentication. No extra software needed.

### VMess + WebSocket
VMess over WebSocket transport. No TLS — best used behind a CDN (e.g. Cloudflare). Widely compatible with most clients.

| Field | Value |
|---|---|
| Network | `ws` |
| AlterId | `0` |
| TLS | none |

### TUIC v5
QUIC-based protocol with BBR congestion control and self-signed TLS. Low latency, similar to Hysteria2.

| Field | Value |
|---|---|
| Congestion | `bbr` |
| ALPN | `h3` |
| TLS | self-signed (insecure=1) |

---

## BBR

Option **8** in the management menu toggles BBR on or off system-wide.

- **Enable** — loads the `tcp_bbr` kernel module, sets `fq` qdisc, writes `/etc/sysctl.d/99-bbr.conf` for persistence across reboots
- **Disable** — reverts to `cubic` + `pfifo_fast`, removes the persistent config

---

## Installation Details

| Path | Purpose |
|---|---|
| `/usr/local/bin/sing-box` | sing-box binary |
| `/usr/local/bin/sb` | Quick-access shortcut |
| `/etc/sing-box/config.json` | Active config |
| `/etc/sing-box/.info` | Saved credentials |
| `/etc/sing-box/cert.pem` | TLS cert (Hysteria2 / TUIC) |
| `/etc/sysctl.d/99-bbr.conf` | BBR persistent config (if enabled) |
| `/etc/systemd/system/sing-box.service` | systemd service |

---

## Client Setup

### v2rayN (Windows) — VLESS Reality

1. Copy the `vless://` link from the output
2. **Servers** → **Import bulk URL from clipboard**
3. Right-click → **Set as active server**
4. Enable system proxy

> **Flow** must be `xtls-rprx-vision`. Without it, the server rejects all connections.

### v2rayN (Windows) — VMess + WebSocket

1. Copy the `vmess://` link from the output
2. **Servers** → **Import bulk URL from clipboard**
3. Right-click → **Set as active server**

### NekoBox / Hiddify / v2rayNG (Android)

Scan the QR code printed after installation, or paste the import link manually.

### SOCKS5 — Any Client

Use the displayed IP, port, and credentials directly in your browser or app's proxy settings.

---

## Service Management

```bash
# Open manager
sb

# Status
systemctl status sing-box

# Restart
systemctl restart sing-box

# Live logs
journalctl -u sing-box -f

# Stop
systemctl stop sing-box
```

---

## Requirements

- Debian 11+ or Ubuntu 20.04+
- Root access
- `curl`, `openssl` (pre-installed on most VPS images)

---

## License

MIT
