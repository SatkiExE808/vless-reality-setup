#!/bin/bash
# sing-box Manager — VLESS Reality + Hysteria2 + SOCKS5
# github.com/SatkiExE808/vless-reality-setup

RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m';  PURPLE='\033[0;35m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

BIN="/usr/local/bin/sing-box"
CFG_DIR="/etc/sing-box"
CFG_FILE="$CFG_DIR/config.json"
INFO_FILE="$CFG_DIR/.info"
SERVICE="/etc/systemd/system/sing-box.service"
SNI="www.microsoft.com"

[[ $EUID -ne 0 ]] && echo -e "${RED}Run as root.${NC}" && exit 1

# ── Helpers ────────────────────────────────────────────────────────────────────

header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}sing-box Proxy Manager${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  github.com/SatkiExE808/vless-reality-setup  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

confirm() { read -rp "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" r; [[ "$r" =~ ^[Yy]$ ]]; }
pause()   { echo ""; read -rp "$(echo -e "${YELLOW}Press Enter to continue...${NC}")"; }
is_installed() { [[ -x "$BIN" && -f "$CFG_FILE" ]]; }

detect_main_ip() {
    MAIN_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+')
    [[ -z "$MAIN_IP" ]] && MAIN_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[\d.]+')
}

detect_ip() {
    # Use main interface IP first (not affected by VPN routing)
    detect_main_ip
    SERVER_IP="$MAIN_IP"
    # Validate it's a public IP; fall back to ipify if it looks private
    case "$SERVER_IP" in
        10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|100.*)
            SERVER_IP=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null)
            [[ -z "$SERVER_IP" ]] && SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
            ;;
    esac
}

# ── Install binary ─────────────────────────────────────────────────────────────

install_binary() {
    if [[ -x "$BIN" ]]; then
        echo -e "${GREEN}✓ sing-box $($BIN version | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1) already installed${NC}"
        return
    fi
    echo -e "${YELLOW}▶ Fetching latest sing-box...${NC}"
    LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    VER=${LATEST#v}
    ARCH=$(uname -m); [[ "$ARCH" == "aarch64" ]] && ARCH="arm64" || ARCH="amd64"
    URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${VER}-linux-${ARCH}.tar.gz"
    curl -sL "$URL" -o /tmp/sb.tar.gz
    tar -xzf /tmp/sb.tar.gz -C /tmp/
    mv /tmp/sing-box-${VER}-linux-${ARCH}/sing-box "$BIN"
    chmod +x "$BIN"
    rm -rf /tmp/sb.tar.gz /tmp/sing-box-${VER}-linux-${ARCH}
    echo -e "${GREEN}✓ Installed sing-box ${VER}${NC}"
}

# ── TLS cert (Hysteria2) ───────────────────────────────────────────────────────

gen_cert() {
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$CFG_DIR/key.pem" -out "$CFG_DIR/cert.pem" \
        -days 36500 -nodes -subj "/CN=${SNI}" 2>/dev/null
    CERT_FP=$(openssl x509 -noout -fingerprint -sha256 -in "$CFG_DIR/cert.pem" \
        | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
}

# ── Inbound JSON builders ──────────────────────────────────────────────────────

json_vless() {
    cat << EOF
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": ${VLESS_PORT},
      "users": [{ "uuid": "${UUID}", "flow": "xtls-rprx-vision" }],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${SNI}", "server_port": 443 },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
EOF
}

json_hy2() {
    cat << EOF
    {
      "type": "hysteria2",
      "tag": "hysteria2",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [{ "password": "${HY2_PASS}" }],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CFG_DIR}/cert.pem",
        "key_path": "${CFG_DIR}/key.pem"
      }
    }
EOF
}

json_socks5() {
    if [[ -n "$SOCKS_USER" ]]; then
        cat << EOF
    {
      "type": "socks",
      "tag": "socks5",
      "listen": "::",
      "listen_port": ${SOCKS_PORT},
      "users": [{ "username": "${SOCKS_USER}", "password": "${SOCKS_PASS}" }]
    }
EOF
    else
        cat << EOF
    {
      "type": "socks",
      "tag": "socks5",
      "listen": "::",
      "listen_port": ${SOCKS_PORT}
    }
EOF
    fi
}

# ── Write config ───────────────────────────────────────────────────────────────

write_config() {
    local parts=()
    [[ $ENABLE_REALITY  == true ]] && parts+=("$(json_vless)")
    [[ $ENABLE_HY2      == true ]] && parts+=("$(json_hy2)")
    [[ $ENABLE_SOCKS5   == true ]] && parts+=("$(json_socks5)")

    local inbounds=""
    for i in "${!parts[@]}"; do
        [[ $i -gt 0 ]] && inbounds+=","$'\n'
        inbounds+="${parts[$i]}"
    done

    cat > "$CFG_FILE" << EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
${inbounds}
  ],
  "outbounds": [{
    "type": "direct",
    "tag": "direct",
    "inet4_bind_address": "${MAIN_IP}"
  }],
  "route": { "rules": [{ "action": "sniff" }], "final": "direct" }
}
EOF
}

# ── Systemd service ────────────────────────────────────────────────────────────

write_service() {
    cat > "$SERVICE" << 'EOF'
[Unit]
Description=sing-box
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
}

# ── QR code ────────────────────────────────────────────────────────────────────

show_qr() {
    if ! command -v qrencode &>/dev/null; then
        apt-get install -y -qq qrencode 2>/dev/null || return
    fi
    echo ""
    qrencode -t ANSIUTF8 "$1"
}

# ── Show connection info ───────────────────────────────────────────────────────

show_info() {
    [[ ! -f "$INFO_FILE" ]] && echo -e "${RED}Not installed.${NC}" && return
    # shellcheck source=/dev/null
    source "$INFO_FILE"
    # SERVER_IP is saved at install time; fall back to live detection only if missing
    [[ -z "$SERVER_IP" ]] && detect_ip

    header
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

    if [[ $ENABLE_REALITY == true ]]; then
        VLESS_LINK="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-${SERVER_IP}"
        echo -e " ${BOLD}${GREEN}◆ VLESS Reality${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
        printf "  %-12s ${GREEN}%s${NC}\n" "Address:"   "$SERVER_IP"
        printf "  %-12s ${GREEN}%s${NC}\n" "Port:"      "$VLESS_PORT"
        printf "  %-12s ${GREEN}%s${NC}\n" "UUID:"      "$UUID"
        printf "  %-12s ${GREEN}%s${NC}\n" "Flow:"      "xtls-rprx-vision"
        printf "  %-12s ${GREEN}%s${NC}\n" "SNI:"       "$SNI"
        printf "  %-12s ${GREEN}%s${NC}\n" "PublicKey:" "$PUBLIC_KEY"
        printf "  %-12s ${GREEN}%s${NC}\n" "ShortID:"   "$SHORT_ID"
        echo ""
        echo -e "  ${YELLOW}▶ Import Link:${NC}"
        echo -e "  ${VLESS_LINK}"
        show_qr "$VLESS_LINK"
    fi

    if [[ $ENABLE_HY2 == true ]]; then
        HY2_LINK="hy2://${HY2_PASS}@${SERVER_IP}:${HY2_PORT}?insecure=1&sni=${SNI}#HY2-${SERVER_IP}"
        echo ""
        echo -e " ${BOLD}${PURPLE}◆ Hysteria2${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
        printf "  %-12s ${GREEN}%s${NC}\n" "Address:"  "$SERVER_IP"
        printf "  %-12s ${GREEN}%s${NC}\n" "Port:"     "$HY2_PORT"
        printf "  %-12s ${GREEN}%s${NC}\n" "Password:" "$HY2_PASS"
        printf "  %-12s ${GREEN}%s${NC}\n" "TLS:"      "self-signed (insecure=1)"
        echo ""
        echo -e "  ${YELLOW}▶ Import Link:${NC}"
        echo -e "  ${HY2_LINK}"
        show_qr "$HY2_LINK"
    fi

    if [[ $ENABLE_SOCKS5 == true ]]; then
        echo ""
        echo -e " ${BOLD}${BLUE}◆ SOCKS5${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
        printf "  %-12s ${GREEN}%s${NC}\n" "Address:"  "$SERVER_IP"
        printf "  %-12s ${GREEN}%s${NC}\n" "Port:"     "$SOCKS_PORT"
        if [[ -n "$SOCKS_USER" ]]; then
            printf "  %-12s ${GREEN}%s${NC}\n" "Username:" "$SOCKS_USER"
            printf "  %-12s ${GREEN}%s${NC}\n" "Password:" "$SOCKS_PASS"
        else
            printf "  %-12s ${GREEN}%s${NC}\n" "Auth:"     "none"
        fi
    fi

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    SB_STATUS=$(systemctl is-active sing-box 2>/dev/null)
    SB_VER=$("$BIN" version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)
    [[ "$SB_STATUS" == "active" ]] \
        && echo -e "  Service : ${GREEN}● running${NC}   Version : ${GREEN}${SB_VER}${NC}" \
        || echo -e "  Service : ${RED}● stopped${NC}   Version : ${SB_VER}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
}

# ── Install flow ───────────────────────────────────────────────────────────────

do_install() {
    header
    echo -e " ${BOLD}Select protocol:${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} VLESS Reality          ${CYAN}(TCP · most secure)${NC}"
    echo -e "  ${GREEN}2.${NC} Hysteria2               ${CYAN}(UDP · fast)${NC}"
    echo -e "  ${GREEN}3.${NC} SOCKS5                  ${CYAN}(TCP · simple)${NC}"
    echo -e "  ${GREEN}4.${NC} VLESS Reality + Hysteria2"
    echo -e "  ${GREEN}5.${NC} VLESS Reality + SOCKS5"
    echo -e "  ${GREEN}6.${NC} All protocols"
    echo ""
    read -rp "$(echo -e "${YELLOW}Choice [1-6, default 1]: ${NC}")" PC
    PC=${PC:-1}

    ENABLE_REALITY=false
    ENABLE_HY2=false
    ENABLE_SOCKS5=false

    case "$PC" in
        1) ENABLE_REALITY=true ;;
        2) ENABLE_HY2=true ;;
        3) ENABLE_SOCKS5=true ;;
        4) ENABLE_REALITY=true; ENABLE_HY2=true ;;
        5) ENABLE_REALITY=true; ENABLE_SOCKS5=true ;;
        6) ENABLE_REALITY=true; ENABLE_HY2=true; ENABLE_SOCKS5=true ;;
        *) echo -e "${RED}Invalid.${NC}"; return ;;
    esac

    echo ""
    if [[ $ENABLE_REALITY == true ]]; then
        read -rp "$(echo -e "${YELLOW}VLESS port [default: 443]: ${NC}")" VLESS_PORT
        VLESS_PORT=${VLESS_PORT:-443}
    fi
    if [[ $ENABLE_HY2 == true ]]; then
        read -rp "$(echo -e "${YELLOW}Hysteria2 port [default: 8443]: ${NC}")" HY2_PORT
        HY2_PORT=${HY2_PORT:-8443}
    fi
    if [[ $ENABLE_SOCKS5 == true ]]; then
        read -rp "$(echo -e "${YELLOW}SOCKS5 port [default: 1080]: ${NC}")" SOCKS_PORT
        SOCKS_PORT=${SOCKS_PORT:-1080}
        read -rp "$(echo -e "${YELLOW}Add authentication? [y/N]: ${NC}")" SOCKS_AUTH
        if [[ "$SOCKS_AUTH" =~ ^[Yy]$ ]]; then
            SOCKS_USER="user$(openssl rand -hex 3)"
            SOCKS_PASS=$(openssl rand -hex 8)
            echo -e "  Generated → ${GREEN}${SOCKS_USER}${NC} / ${GREEN}${SOCKS_PASS}${NC}"
        else
            SOCKS_USER=""
            SOCKS_PASS=""
        fi
    fi

    detect_ip
    detect_main_ip
    install_binary
    mkdir -p "$CFG_DIR"
    echo -e "${YELLOW}▶ Generating credentials...${NC}"

    UUID=$("$BIN" generate uuid)
    KEYPAIR=$("$BIN" generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/PrivateKey/{print $2}')
    PUBLIC_KEY=$(echo  "$KEYPAIR" | awk '/PublicKey/{print $2}')
    SHORT_ID=$(openssl rand -hex 8)
    HY2_PASS=$(openssl rand -hex 16)
    CERT_FP=""

    [[ $ENABLE_HY2 == true ]] && gen_cert

    write_config

    "$BIN" check -c "$CFG_FILE" || { echo -e "${RED}Config check failed.${NC}"; exit 1; }
    echo -e "${GREEN}✓ Config valid${NC}"

    cat > "$INFO_FILE" << EOF
ENABLE_REALITY=${ENABLE_REALITY}
ENABLE_HY2=${ENABLE_HY2}
ENABLE_SOCKS5=${ENABLE_SOCKS5}
SERVER_IP=${SERVER_IP}
UUID=${UUID}
PRIVATE_KEY=${PRIVATE_KEY}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
VLESS_PORT=${VLESS_PORT:-443}
HY2_PORT=${HY2_PORT:-8443}
HY2_PASS=${HY2_PASS}
SOCKS_PORT=${SOCKS_PORT:-1080}
SOCKS_USER=${SOCKS_USER}
SOCKS_PASS=${SOCKS_PASS}
CERT_FP=${CERT_FP}
MAIN_IP=${MAIN_IP}
EOF

    write_service

    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}✓ sing-box is running${NC}"
    else
        echo -e "${RED}✗ Failed to start. Run: journalctl -u sing-box -n 30${NC}"
        exit 1
    fi

    show_info
}

# ── Update binary ──────────────────────────────────────────────────────────────

do_update() {
    header
    echo -e "${YELLOW}▶ Checking for updates...${NC}"
    LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    LATEST_VER=${LATEST#v}
    CURRENT=$("$BIN" version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)

    if [[ "$CURRENT" == "$LATEST_VER" ]]; then
        echo -e "${GREEN}Already on latest: ${CURRENT}${NC}"
        return
    fi

    echo -e "Updating ${RED}${CURRENT}${NC} → ${GREEN}${LATEST_VER}${NC}"
    systemctl stop sing-box
    ARCH=$(uname -m); [[ "$ARCH" == "aarch64" ]] && ARCH="arm64" || ARCH="amd64"
    URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${LATEST_VER}-linux-${ARCH}.tar.gz"
    curl -sL "$URL" -o /tmp/sb.tar.gz
    tar -xzf /tmp/sb.tar.gz -C /tmp/
    mv /tmp/sing-box-${LATEST_VER}-linux-${ARCH}/sing-box "$BIN"
    chmod +x "$BIN"
    rm -rf /tmp/sb.tar.gz /tmp/sing-box-${LATEST_VER}-linux-${ARCH}
    systemctl start sing-box
    echo -e "${GREEN}✓ Updated to $($BIN version | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)${NC}"
}

# ── Uninstall ──────────────────────────────────────────────────────────────────

do_uninstall() {
    header
    echo -e "${RED}This will completely remove sing-box.${NC}"
    confirm "Continue?" || { echo "Cancelled."; return; }
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    rm -f "$SERVICE" "$BIN"
    rm -rf "$CFG_DIR"
    systemctl daemon-reload
    echo -e "${GREEN}✓ Uninstalled.${NC}"
}

# ── Main menu ──────────────────────────────────────────────────────────────────

main_menu() {
    while true; do
        header

        if is_installed; then
            SB_STATUS=$(systemctl is-active sing-box 2>/dev/null)
            SB_VER=$("$BIN" version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)
            [[ "$SB_STATUS" == "active" ]] \
                && echo -e "  Status : ${GREEN}● running${NC}   Version : ${GREEN}${SB_VER}${NC}" \
                || echo -e "  Status : ${RED}● stopped${NC}   Version : ${SB_VER}"
        else
            echo -e "  Status : ${YELLOW}not installed${NC}"
        fi
        echo ""

        if ! is_installed; then
            echo -e "  ${GREEN}1.${NC} Install"
            echo ""
            echo -e "  ${RED}0.${NC} Exit"
        else
            echo -e "  ${GREEN}1.${NC} Show Config & Links"
            echo -e "  ${GREEN}2.${NC} Restart Service"
            echo -e "  ${GREEN}3.${NC} Stop / Start Service"
            echo -e "  ${GREEN}4.${NC} View Logs"
            echo -e "  ${GREEN}5.${NC} Update sing-box"
            echo -e "  ${GREEN}6.${NC} Reinstall"
            echo -e "  ${RED}7.${NC} Uninstall"
            echo ""
            echo -e "  ${RED}0.${NC} Exit"
        fi

        echo ""
        read -rp "$(echo -e "${YELLOW}Select [0-7]: ${NC}")" OPT

        case "$OPT" in
            1)
                if is_installed; then show_info; else do_install; fi
                pause ;;
            2)
                systemctl restart sing-box \
                    && echo -e "${GREEN}✓ Restarted.${NC}" \
                    || echo -e "${RED}✗ Failed.${NC}"
                pause ;;
            3)
                if [[ "$(systemctl is-active sing-box 2>/dev/null)" == "active" ]]; then
                    systemctl stop  sing-box && echo -e "${YELLOW}● Stopped.${NC}"
                else
                    systemctl start sing-box && echo -e "${GREEN}● Started.${NC}"
                fi
                pause ;;
            4)
                journalctl -u sing-box -n 60 --no-pager
                pause ;;
            5) do_update;    pause ;;
            6) do_uninstall; do_install; pause ;;
            7) do_uninstall; pause ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
