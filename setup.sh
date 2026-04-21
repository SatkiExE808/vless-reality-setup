#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Run as root.${NC}" && exit 1

PORT=${1:-443}
SNI="www.microsoft.com"
BIN="/usr/local/bin/sing-box"
CFG_DIR="/etc/sing-box"

echo -e "${CYAN}=== VLESS Reality Installer ===${NC}"

# ── 1. Public IP ──────────────────────────────────────────────────────────────
SERVER_IP=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null)
[[ -z "$SERVER_IP" ]] && SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org)
echo -e "Server IP : ${GREEN}${SERVER_IP}${NC}"
echo -e "Port      : ${GREEN}${PORT}${NC}"

# ── 2. Install sing-box if missing ────────────────────────────────────────────
if [[ ! -x "$BIN" ]]; then
    echo -e "${YELLOW}Installing sing-box...${NC}"
    LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    VERSION=${LATEST#v}
    ARCH=$(uname -m); [[ "$ARCH" == "aarch64" ]] && ARCH="arm64" || ARCH="amd64"
    URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${VERSION}-linux-${ARCH}.tar.gz"
    curl -sL "$URL" -o /tmp/sb.tar.gz
    tar -xzf /tmp/sb.tar.gz -C /tmp/
    mv /tmp/sing-box-${VERSION}-linux-${ARCH}/sing-box "$BIN"
    chmod +x "$BIN"
    rm -rf /tmp/sb.tar.gz /tmp/sing-box-${VERSION}-linux-${ARCH}
    echo -e "${GREEN}Installed $($BIN version | head -1)${NC}"
else
    echo -e "${GREEN}sing-box already installed: $($BIN version | head -1)${NC}"
fi

# ── 3. Generate credentials ───────────────────────────────────────────────────
UUID=$("$BIN" generate uuid)
KEYPAIR=$("$BIN" generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/PrivateKey/{print $2}')
PUBLIC_KEY=$(echo "$KEYPAIR"  | awk '/PublicKey/{print $2}')
SHORT_ID=$(openssl rand -hex 8)

# ── 4. Write config ───────────────────────────────────────────────────────────
mkdir -p "$CFG_DIR"
cat > "${CFG_DIR}/config.json" << EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      }
    ],
    "final": "direct"
  }
}
EOF

# ── 5. Validate config ────────────────────────────────────────────────────────
"$BIN" check -c "${CFG_DIR}/config.json" || { echo -e "${RED}Config invalid.${NC}"; exit 1; }

# ── 6. Systemd service ────────────────────────────────────────────────────────
cat > /etc/systemd/system/sing-box.service << 'EOF'
[Unit]
Description=sing-box VLESS Reality
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box --quiet
systemctl restart sing-box
sleep 2

# ── 7. Verify ─────────────────────────────────────────────────────────────────
if ! systemctl is-active --quiet sing-box; then
    echo -e "${RED}sing-box failed to start:${NC}"
    journalctl -u sing-box -n 20 --no-pager
    exit 1
fi

# ── 8. Output ─────────────────────────────────────────────────────────────────
LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-${SERVER_IP}"

echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  VLESS Reality Ready${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
printf "  %-12s %s\n" "Address:"   "$SERVER_IP"
printf "  %-12s %s\n" "Port:"      "$PORT"
printf "  %-12s %s\n" "UUID:"      "$UUID"
printf "  %-12s %s\n" "Flow:"      "xtls-rprx-vision"
printf "  %-12s %s\n" "SNI:"       "$SNI"
printf "  %-12s %s\n" "PublicKey:" "$PUBLIC_KEY"
printf "  %-12s %s\n" "ShortID:"   "$SHORT_ID"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Import link:${NC}"
echo "$LINK"
echo ""
