# VLESS Reality Setup

One-command [sing-box](https://github.com/SagerNet/sing-box) VLESS + Reality installer for any Debian/Ubuntu VPS.

- Automatically installs the latest sing-box
- Generates fresh UUID, Reality keypair, and Short ID
- Creates and validates the config
- Registers and starts a systemd service
- Prints a ready-to-import VLESS link

---

## Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/SatkiExE808/vless-reality-setup/main/setup.sh)
```

Custom port (default is `443`):

```bash
bash <(curl -sL https://raw.githubusercontent.com/SatkiExE808/vless-reality-setup/main/setup.sh) 8443
```

> Requires root. Tested on Debian 12 / Ubuntu 22+.

---

## What Gets Installed

| Path | Purpose |
|---|---|
| `/usr/local/bin/sing-box` | sing-box binary |
| `/etc/sing-box/config.json` | VLESS Reality config |
| `/etc/systemd/system/sing-box.service` | systemd service |

---

## Output Example

```
════════════════════════════════════════
  VLESS Reality Ready
════════════════════════════════════════
  Address:     1.2.3.4
  Port:        443
  UUID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Flow:        xtls-rprx-vision
  SNI:         www.microsoft.com
  PublicKey:   xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  ShortID:     xxxxxxxxxxxxxxxx
════════════════════════════════════════

Import link:
vless://...
```

Copy the import link and add it to your client.

---

## Client Setup (v2rayN)

1. Copy the `vless://` link from the output
2. In v2rayN → **Servers** → **Import bulk URL from clipboard**
3. Right-click the new server → **Set as active server**
4. Enable system proxy

> Make sure **Flow** is set to `xtls-rprx-vision` in the server config. Without it, all connections will be rejected.

---

## Manage the Service

```bash
# Status
systemctl status sing-box

# Restart
systemctl restart sing-box

# Logs
journalctl -u sing-box -f

# Stop
systemctl stop sing-box
```

---

## Configuration Details

| Field | Value |
|---|---|
| Protocol | VLESS |
| Security | Reality |
| Flow | `xtls-rprx-vision` |
| SNI | `www.microsoft.com` |
| Fingerprint | `chrome` |
| Transport | TCP |
| Port | `443` (default) |

Reality uses the real TLS certificate of the SNI target (`www.microsoft.com`), making the traffic indistinguishable from normal HTTPS — no self-signed certs, no TLS fingerprint leaks.

---

## Requirements

- Debian 11+ or Ubuntu 20.04+
- Root access
- `curl`, `openssl` (pre-installed on most VPS images)

---

## License

MIT
