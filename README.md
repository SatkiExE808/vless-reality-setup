# sing-box VLESS Reality Manager

A clean, interactive installer and manager for [sing-box](https://github.com/SagerNet/sing-box) with **VLESS Reality** and **Hysteria2** support.

- Interactive menu — install, manage, update, uninstall
- Auto-installs latest sing-box binary
- Generates fresh UUID, Reality keypair, and Short ID on every install
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

## Menu

```
╔══════════════════════════════════════════════╗
║  sing-box VLESS Reality Manager              ║
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

| Protocol | Transport | Use Case |
|---|---|---|
| **VLESS Reality** | TCP | Most secure, indistinguishable from real HTTPS |
| **Hysteria2** | UDP (QUIC) | High speed, low latency |
| **Both** | TCP + UDP | Best of both |

### VLESS Reality

Uses the real TLS certificate of `www.microsoft.com` via the Reality protocol. Traffic looks exactly like a normal HTTPS connection — no self-signed certs, no detectable fingerprints.

| Field | Value |
|---|---|
| Flow | `xtls-rprx-vision` |
| SNI | `www.microsoft.com` |
| Fingerprint | `chrome` |
| Transport | TCP |

### Hysteria2

Self-signed certificate with QUIC transport. Ideal for high-bandwidth or high-latency connections.

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

### v2rayN (Windows)

1. Copy the `vless://` link from the output
2. **Servers** → **Import bulk URL from clipboard**
3. Right-click → **Set as active server**
4. Enable system proxy

> The **Flow** field must be `xtls-rprx-vision`. If missing, all connections will be rejected by the server.

### NekoBox / Hiddify / v2rayNG (Android)

Scan the QR code printed after installation, or paste the import link manually.

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
