# sing-box Proxy Manager

A clean, interactive installer and manager for [sing-box](https://github.com/SagerNet/sing-box) — supports **VLESS Reality**, **Hysteria2**, and **SOCKS5** in any combination.

- Interactive menu — install, manage, update, uninstall
- Auto-installs latest sing-box binary
- Mix and match protocols on the same server
- QR code output for mobile clients
- Supports `amd64` and `arm64`
- Tested on Debian 11/12 and Ubuntu 20.04+

---

## Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/SatkiExE808/vless-reality-setup/main/setup.sh)
```

> Requires root. Run on a fresh Debian/Ubuntu VPS.

---

## Protocol Menu

```
  1. VLESS Reality          (TCP · most secure)
  2. Hysteria2              (UDP · fast)
  3. SOCKS5                 (TCP · simple)
  4. VLESS Reality + Hysteria2
  5. VLESS Reality + SOCKS5
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
  2. Restart Service
  3. Stop / Start Service
  4. View Logs
  5. Update sing-box
  6. Reinstall
  7. Uninstall

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

---

## Installation Details

| Path | Purpose |
|---|---|
| `/usr/local/bin/sing-box` | sing-box binary |
| `/etc/sing-box/config.json` | Active config |
| `/etc/sing-box/.info` | Saved credentials |
| `/etc/sing-box/cert.pem` | TLS cert (Hysteria2 only) |
| `/etc/systemd/system/sing-box.service` | systemd service |

---

## Client Setup

### v2rayN (Windows) — VLESS Reality

1. Copy the `vless://` link from the output
2. **Servers** → **Import bulk URL from clipboard**
3. Right-click → **Set as active server**
4. Enable system proxy

> **Flow** must be `xtls-rprx-vision`. Without it, the server rejects all connections.

### NekoBox / Hiddify / v2rayNG (Android)

Scan the QR code printed after installation, or paste the import link manually.

### SOCKS5 — Any Client

Use the displayed IP, port, and credentials directly in your browser or app's proxy settings.

---

## Service Management

```bash
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

## Re-run the Manager

```bash
bash <(curl -sL https://raw.githubusercontent.com/SatkiExE808/vless-reality-setup/main/setup.sh)
```

---

## Requirements

- Debian 11+ or Ubuntu 20.04+
- Root access
- `curl`, `openssl` (pre-installed on most VPS images)

---

## License

MIT
