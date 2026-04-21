#!/bin/bash
# sing-box Manager — VLESS Reality + Hysteria2 + SOCKS5 + VMess/WS + TUIC
# github.com/SatkiExE808/vless-reality-setup

RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m';  PURPLE='\033[0;35m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

BIN="/usr/local/bin/sing-box"
CFG_DIR="/etc/sing-box"
CFG_FILE="$CFG_DIR/config.json"
INFO_FILE="$CFG_DIR/.info"
SERVICE="/etc/systemd/system/sing-box.service"
SHORTCUT="/usr/local/bin/sb"
SNI="www.microsoft.com"

[[ $EUID -ne 0 ]] && echo -e "${RED}Run as root.${NC}" && exit 1

for _dep in curl openssl; do
    command -v "$_dep" &>/dev/null || { echo -e "${RED}Missing dependency: $_dep${NC}"; exit 1; }
done

# ── Helpers ────────────────────────────────────────────────────────────────────

header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}sing-box Proxy Manager${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  github.com/SatkiExE808/vless-reality-setup  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

confirm()      { read -rp "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" r; [[ "$r" =~ ^[Yy]$ ]]; }
pause()        { echo ""; read -rp "$(echo -e "${YELLOW}Press Enter to continue...${NC}")"; }
is_installed() { [[ -x "$BIN" && -f "$CFG_FILE" ]]; }

validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }

read_port() {
    # read_port "Label" default VARNAME
    local _label="$1" _def="$2"
    while true; do
        read -rp "$(echo -e "${YELLOW}${_label} port [default: ${_def}]: ${NC}")" _pt
        _pt=${_pt:-$_def}
        if validate_port "$_pt"; then
            printf -v "$3" '%s' "$_pt"
            return
        fi
        echo -e "${RED}  Invalid — enter a number between 1 and 65535.${NC}"
    done
}

detect_main_ip() {
    MAIN_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+')
    [[ -z "$MAIN_IP" ]] && MAIN_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[\d.]+')
}

detect_ip() {
    detect_main_ip
    SERVER_IP="$MAIN_IP"
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
    local LATEST VER ARCH URL
    LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    [[ -z "$LATEST" ]] && echo -e "${RED}Failed to fetch release info.${NC}" && return 1
    VER=${LATEST#v}
    ARCH=$(uname -m); [[ "$ARCH" == "aarch64" ]] && ARCH="arm64" || ARCH="amd64"
    URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${VER}-linux-${ARCH}.tar.gz"
    curl -sL "$URL" -o /tmp/sb.tar.gz || { echo -e "${RED}Download failed.${NC}"; return 1; }
    tar -xzf /tmp/sb.tar.gz -C /tmp/ || { echo -e "${RED}Extract failed.${NC}"; rm -f /tmp/sb.tar.gz; return 1; }
    mv /tmp/sing-box-${VER}-linux-${ARCH}/sing-box "$BIN"
    chmod +x "$BIN"
    rm -rf /tmp/sb.tar.gz /tmp/sing-box-${VER}-linux-${ARCH}
    echo -e "${GREEN}✓ Installed sing-box ${VER}${NC}"
}

# ── TLS cert (Hysteria2 / TUIC) ────────────────────────────────────────────────

gen_cert() {
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$CFG_DIR/key.pem" -out "$CFG_DIR/cert.pem" \
        -days 36500 -nodes -subj "/CN=${SNI}" 2>/dev/null
    CERT_FP=$(openssl x509 -noout -fingerprint -sha256 -in "$CFG_DIR/cert.pem" \
        | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
}

# Read fingerprint from existing cert without regenerating
read_cert_fp() {
    CERT_FP=$(openssl x509 -noout -fingerprint -sha256 -in "$CFG_DIR/cert.pem" 2>/dev/null \
        | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
}

# Only generate cert if one does not exist; otherwise just read its fingerprint
ensure_cert() {
    if [[ -f "$CFG_DIR/cert.pem" ]]; then
        read_cert_fp
    else
        gen_cert
    fi
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

json_vmess() {
    cat << EOF
    {
      "type": "vmess",
      "tag": "vmess-ws",
      "listen": "::",
      "listen_port": ${VMESS_PORT},
      "users": [{ "uuid": "${VMESS_UUID}", "alterId": 0 }],
      "transport": {
        "type": "ws",
        "path": "/${VMESS_PATH}"
      }
    }
EOF
}

json_tuic() {
    cat << EOF
    {
      "type": "tuic",
      "tag": "tuic",
      "listen": "::",
      "listen_port": ${TUIC_PORT},
      "users": [{ "uuid": "${TUIC_UUID}", "password": "${TUIC_PASS}" }],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CFG_DIR}/cert.pem",
        "key_path": "${CFG_DIR}/key.pem"
      }
    }
EOF
}

# ── Write config ───────────────────────────────────────────────────────────────

write_config() {
    local parts=()
    [[ $ENABLE_REALITY  == true ]] && parts+=("$(json_vless)")
    [[ $ENABLE_HY2      == true ]] && parts+=("$(json_hy2)")
    [[ $ENABLE_SOCKS5   == true ]] && parts+=("$(json_socks5)")
    [[ $ENABLE_VMESS    == true ]] && parts+=("$(json_vmess)")
    [[ $ENABLE_TUIC     == true ]] && parts+=("$(json_tuic)")

    local inbounds=""
    for i in "${!parts[@]}"; do
        [[ $i -gt 0 ]] && inbounds+=","$'\n'
        inbounds+="${parts[$i]}"
    done

    # Only bind to MAIN_IP if detection succeeded
    local OUTBOUND
    if [[ -n "$MAIN_IP" ]]; then
        OUTBOUND="{\"type\":\"direct\",\"tag\":\"direct\",\"inet4_bind_address\":\"${MAIN_IP}\"}"
    else
        OUTBOUND="{\"type\":\"direct\",\"tag\":\"direct\"}"
    fi

    cat > "$CFG_FILE" << EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
${inbounds}
  ],
  "outbounds": [${OUTBOUND}],
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

    if [[ $ENABLE_VMESS == true ]]; then
        local VMESS_JSON="{\"v\":\"2\",\"ps\":\"VMess-${SERVER_IP}\",\"add\":\"${SERVER_IP}\",\"port\":${VMESS_PORT},\"id\":\"${VMESS_UUID}\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/${VMESS_PATH}\",\"tls\":\"\"}"
        VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
        echo ""
        echo -e " ${BOLD}${YELLOW}◆ VMess + WebSocket${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
        printf "  %-12s ${GREEN}%s${NC}\n" "Address:"   "$SERVER_IP"
        printf "  %-12s ${GREEN}%s${NC}\n" "Port:"      "$VMESS_PORT"
        printf "  %-12s ${GREEN}%s${NC}\n" "UUID:"      "$VMESS_UUID"
        printf "  %-12s ${GREEN}%s${NC}\n" "Network:"   "ws"
        printf "  %-12s ${GREEN}%s${NC}\n" "Path:"      "/${VMESS_PATH}"
        printf "  %-12s ${GREEN}%s${NC}\n" "TLS:"       "none"
        echo ""
        echo -e "  ${YELLOW}▶ Import Link:${NC}"
        echo -e "  ${VMESS_LINK}"
        show_qr "$VMESS_LINK"
    fi

    if [[ $ENABLE_TUIC == true ]]; then
        TUIC_LINK="tuic://${TUIC_UUID}:${TUIC_PASS}@${SERVER_IP}:${TUIC_PORT}?congestion_control=bbr&alpn=h3&allow_insecure=1&sni=${SNI}#TUIC-${SERVER_IP}"
        echo ""
        echo -e " ${BOLD}${PURPLE}◆ TUIC v5${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
        printf "  %-12s ${GREEN}%s${NC}\n" "Address:"    "$SERVER_IP"
        printf "  %-12s ${GREEN}%s${NC}\n" "Port:"       "$TUIC_PORT"
        printf "  %-12s ${GREEN}%s${NC}\n" "UUID:"       "$TUIC_UUID"
        printf "  %-12s ${GREEN}%s${NC}\n" "Password:"   "$TUIC_PASS"
        printf "  %-12s ${GREEN}%s${NC}\n" "Congestion:" "bbr"
        printf "  %-12s ${GREEN}%s${NC}\n" "TLS:"        "self-signed (insecure=1)"
        echo ""
        echo -e "  ${YELLOW}▶ Import Link:${NC}"
        echo -e "  ${TUIC_LINK}"
        show_qr "$TUIC_LINK"
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
    local SB_STATUS SB_VER
    SB_STATUS=$(systemctl is-active sing-box 2>/dev/null)
    SB_VER=$("$BIN" version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)
    [[ "$SB_STATUS" == "active" ]] \
        && echo -e "  Service : ${GREEN}● running${NC}   Version : ${GREEN}${SB_VER}${NC}" \
        || echo -e "  Service : ${RED}● stopped${NC}   Version : ${SB_VER}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
}

# ── Write info file ────────────────────────────────────────────────────────────

write_info() {
    cat > "$INFO_FILE" << EOF
ENABLE_REALITY=${ENABLE_REALITY}
ENABLE_HY2=${ENABLE_HY2}
ENABLE_SOCKS5=${ENABLE_SOCKS5}
ENABLE_VMESS=${ENABLE_VMESS}
ENABLE_TUIC=${ENABLE_TUIC}
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
VMESS_PORT=${VMESS_PORT:-8080}
VMESS_UUID=${VMESS_UUID}
VMESS_PATH=${VMESS_PATH}
TUIC_PORT=${TUIC_PORT:-8853}
TUIC_UUID=${TUIC_UUID}
TUIC_PASS=${TUIC_PASS}
CERT_FP=${CERT_FP}
MAIN_IP=${MAIN_IP}
EOF
    chmod 600 "$INFO_FILE"
}

# ── Install flow ───────────────────────────────────────────────────────────────

do_install() {
    header
    echo -e " ${BOLD}Select protocol:${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} VLESS Reality          ${CYAN}(TCP · most secure)${NC}"
    echo -e "  ${GREEN}2.${NC} Hysteria2               ${CYAN}(UDP · fast)${NC}"
    echo -e "  ${GREEN}3.${NC} VMess + WebSocket       ${CYAN}(TCP · compatible)${NC}"
    echo -e "  ${GREEN}4.${NC} TUIC                    ${CYAN}(UDP · fast · QUIC)${NC}"
    echo -e "  ${GREEN}5.${NC} SOCKS5                  ${CYAN}(TCP · simple)${NC}"
    echo -e "  ${GREEN}6.${NC} All protocols"
    echo ""
    read -rp "$(echo -e "${YELLOW}Choice [1-6, default 1]: ${NC}")" PC
    PC=${PC:-1}

    ENABLE_REALITY=false; ENABLE_HY2=false; ENABLE_SOCKS5=false
    ENABLE_VMESS=false;   ENABLE_TUIC=false

    case "$PC" in
        1) ENABLE_REALITY=true ;;
        2) ENABLE_HY2=true ;;
        3) ENABLE_VMESS=true ;;
        4) ENABLE_TUIC=true ;;
        5) ENABLE_SOCKS5=true ;;
        6) ENABLE_REALITY=true; ENABLE_HY2=true; ENABLE_SOCKS5=true; ENABLE_VMESS=true; ENABLE_TUIC=true ;;
        *) echo -e "${RED}Invalid.${NC}"; return ;;
    esac

    echo ""
    [[ $ENABLE_REALITY == true ]] && read_port "VLESS"    443  VLESS_PORT
    [[ $ENABLE_HY2     == true ]] && read_port "Hysteria2" 8443 HY2_PORT
    [[ $ENABLE_VMESS   == true ]] && read_port "VMess+WS"  8080 VMESS_PORT
    [[ $ENABLE_TUIC    == true ]] && read_port "TUIC"      8853 TUIC_PORT
    if [[ $ENABLE_SOCKS5 == true ]]; then
        read_port "SOCKS5" 1080 SOCKS_PORT
        read -rp "$(echo -e "${YELLOW}Add authentication? [y/N]: ${NC}")" SOCKS_AUTH
        if [[ "$SOCKS_AUTH" =~ ^[Yy]$ ]]; then
            SOCKS_USER="user$(openssl rand -hex 3)"
            SOCKS_PASS=$(openssl rand -hex 8)
            echo -e "  Generated → ${GREEN}${SOCKS_USER}${NC} / ${GREEN}${SOCKS_PASS}${NC}"
        else
            SOCKS_USER=""; SOCKS_PASS=""
        fi
    fi

    detect_ip
    echo ""
    echo -e "  Auto-detected IP : ${GREEN}${SERVER_IP}${NC}"
    echo -e "  ${CYAN}(On NAT VPS the detected IP may differ from the IP clients connect to)${NC}"
    read -rp "$(echo -e "${YELLOW}Server IP [${SERVER_IP}]: ${NC}")" INPUT_IP
    [[ -n "$INPUT_IP" ]] && SERVER_IP="$INPUT_IP"

    install_binary || return 1
    mkdir -p "$CFG_DIR"
    echo -e "${YELLOW}▶ Generating credentials...${NC}"

    UUID=$("$BIN" generate uuid)
    KEYPAIR=$("$BIN" generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/PrivateKey/{print $2}')
    PUBLIC_KEY=$(echo  "$KEYPAIR" | awk '/PublicKey/{print $2}')
    SHORT_ID=$(openssl rand -hex 8)
    HY2_PASS=$(openssl rand -hex 16)
    VMESS_UUID=$("$BIN" generate uuid)
    VMESS_PATH=$(openssl rand -hex 4)
    TUIC_UUID=$("$BIN" generate uuid)
    TUIC_PASS=$(openssl rand -hex 16)
    CERT_FP=""

    [[ $ENABLE_HY2 == true || $ENABLE_TUIC == true ]] && gen_cert

    write_config

    if ! "$BIN" check -c "$CFG_FILE" 2>&1; then
        echo -e "${RED}Config check failed — please report this issue.${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Config valid${NC}"

    write_info
    write_service

    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}✓ sing-box is running${NC}"
    else
        echo -e "${RED}✗ Failed to start. Check: journalctl -u sing-box -n 30${NC}"
        return 1
    fi

    show_info
}

# ── Add / Delete protocol ─────────────────────────────────────────────────────

do_add_protocol() {
    [[ ! -f "$INFO_FILE" ]] && echo -e "${RED}Not installed.${NC}" && return
    source "$INFO_FILE"

    header
    echo -e " ${BOLD}Add a protocol:${NC}"
    echo ""

    # Active protocols — shown in main menu order
    local ANY_ACTIVE=false
    [[ $ENABLE_REALITY == true ]] && echo -e "  ${CYAN}✓  VLESS Reality${NC}"      && ANY_ACTIVE=true
    [[ $ENABLE_HY2     == true ]] && echo -e "  ${CYAN}✓  Hysteria2${NC}"          && ANY_ACTIVE=true
    [[ $ENABLE_VMESS   == true ]] && echo -e "  ${CYAN}✓  VMess + WebSocket${NC}"  && ANY_ACTIVE=true
    [[ $ENABLE_TUIC    == true ]] && echo -e "  ${CYAN}✓  TUIC${NC}"               && ANY_ACTIVE=true
    [[ $ENABLE_SOCKS5  == true ]] && echo -e "  ${CYAN}✓  SOCKS5${NC}"             && ANY_ACTIVE=true
    [[ $ANY_ACTIVE == true ]] && echo ""

    # Available protocols — in same order
    local -a _NAMES _DESCS _IDS
    [[ $ENABLE_REALITY != true ]] && _NAMES+=("VLESS Reality")     && _DESCS+=("TCP · most secure") && _IDS+=("reality")
    [[ $ENABLE_HY2     != true ]] && _NAMES+=("Hysteria2")         && _DESCS+=("UDP · fast")        && _IDS+=("hy2")
    [[ $ENABLE_VMESS   != true ]] && _NAMES+=("VMess + WebSocket") && _DESCS+=("TCP · compatible")  && _IDS+=("vmess")
    [[ $ENABLE_TUIC    != true ]] && _NAMES+=("TUIC")              && _DESCS+=("UDP · fast · QUIC") && _IDS+=("tuic")
    [[ $ENABLE_SOCKS5  != true ]] && _NAMES+=("SOCKS5")            && _DESCS+=("TCP · simple")      && _IDS+=("socks5")

    if [[ ${#_NAMES[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}All protocols are already active.${NC}"
        return
    fi

    for i in "${!_NAMES[@]}"; do
        printf "  ${GREEN}%d.${NC}  %-22s ${CYAN}(%s)${NC}\n" $((i+1)) "${_NAMES[$i]}" "${_DESCS[$i]}"
    done
    echo -e "  ${RED}0.${NC}  Back"

    echo ""
    read -rp "$(echo -e "${YELLOW}Choice [0-${#_NAMES[@]}]: ${NC}")" ADD_CHOICE

    [[ "$ADD_CHOICE" == "0" ]] && return
    if ! [[ "$ADD_CHOICE" =~ ^[0-9]+$ ]] || (( ADD_CHOICE < 1 || ADD_CHOICE > ${#_NAMES[@]} )); then
        echo -e "${RED}Invalid.${NC}"; return
    fi

    local _SEL="${_IDS[$((ADD_CHOICE-1))]}"

    case "$_SEL" in
        reality)
            read_port "VLESS" 443 VLESS_PORT
            KEYPAIR=$("$BIN" generate reality-keypair)
            UUID=$("$BIN" generate uuid)
            PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/PrivateKey/{print $2}')
            PUBLIC_KEY=$(echo  "$KEYPAIR" | awk '/PublicKey/{print $2}')
            SHORT_ID=$(openssl rand -hex 8)
            ENABLE_REALITY=true ;;
        hy2)
            read_port "Hysteria2" 8443 HY2_PORT
            HY2_PASS=$(openssl rand -hex 16)
            ensure_cert
            ENABLE_HY2=true ;;
        socks5)
            read_port "SOCKS5" 1080 SOCKS_PORT
            read -rp "$(echo -e "${YELLOW}Add authentication? [y/N]: ${NC}")" SOCKS_AUTH
            if [[ "$SOCKS_AUTH" =~ ^[Yy]$ ]]; then
                SOCKS_USER="user$(openssl rand -hex 3)"
                SOCKS_PASS=$(openssl rand -hex 8)
                echo -e "  Generated → ${GREEN}${SOCKS_USER}${NC} / ${GREEN}${SOCKS_PASS}${NC}"
            else
                SOCKS_USER=""; SOCKS_PASS=""
            fi
            ENABLE_SOCKS5=true ;;
        vmess)
            read_port "VMess+WS" 8080 VMESS_PORT
            VMESS_UUID=$("$BIN" generate uuid)
            VMESS_PATH=$(openssl rand -hex 4)
            ENABLE_VMESS=true ;;
        tuic)
            read_port "TUIC" 8853 TUIC_PORT
            TUIC_UUID=$("$BIN" generate uuid)
            TUIC_PASS=$(openssl rand -hex 16)
            ensure_cert
            ENABLE_TUIC=true ;;
    esac

    detect_main_ip
    write_config
    if ! "$BIN" check -c "$CFG_FILE" 2>&1; then
        echo -e "${RED}Config invalid.${NC}"; return
    fi

    write_info
    systemctl restart sing-box
    sleep 1
    echo -e "${GREEN}✓ Protocol added and service restarted.${NC}"
    show_info
}

do_delete_protocol() {
    [[ ! -f "$INFO_FILE" ]] && echo -e "${RED}Not installed.${NC}" && return
    source "$INFO_FILE"

    local COUNT=0
    [[ $ENABLE_REALITY == true ]] && ((COUNT++))
    [[ $ENABLE_HY2     == true ]] && ((COUNT++))
    [[ $ENABLE_SOCKS5  == true ]] && ((COUNT++))
    [[ $ENABLE_VMESS   == true ]] && ((COUNT++))
    [[ $ENABLE_TUIC    == true ]] && ((COUNT++))

    if [[ $COUNT -le 1 ]]; then
        echo -e "${RED}Only one protocol active. Use Uninstall instead.${NC}"
        return
    fi

    local -a _NAMES _IDS
    [[ $ENABLE_REALITY == true ]] && _NAMES+=("VLESS Reality")     && _IDS+=("reality")
    [[ $ENABLE_HY2     == true ]] && _NAMES+=("Hysteria2")         && _IDS+=("hy2")
    [[ $ENABLE_VMESS   == true ]] && _NAMES+=("VMess + WebSocket") && _IDS+=("vmess")
    [[ $ENABLE_TUIC    == true ]] && _NAMES+=("TUIC")              && _IDS+=("tuic")
    [[ $ENABLE_SOCKS5  == true ]] && _NAMES+=("SOCKS5")            && _IDS+=("socks5")

    header
    echo -e " ${BOLD}Remove a protocol:${NC}"
    echo ""

    for i in "${!_NAMES[@]}"; do
        echo -e "  ${GREEN}$((i+1)).${NC}  ${_NAMES[$i]}"
    done
    echo -e "  ${RED}0.${NC}  Back"

    echo ""
    read -rp "$(echo -e "${YELLOW}Choice [0-${#_NAMES[@]}]: ${NC}")" DEL_CHOICE

    [[ "$DEL_CHOICE" == "0" ]] && return
    if ! [[ "$DEL_CHOICE" =~ ^[0-9]+$ ]] || (( DEL_CHOICE < 1 || DEL_CHOICE > ${#_NAMES[@]} )); then
        echo -e "${RED}Invalid.${NC}"; return
    fi

    local _SEL="${_IDS[$((DEL_CHOICE-1))]}"
    local _LABEL="${_NAMES[$((DEL_CHOICE-1))]}"

    confirm "Remove ${_LABEL}?" || return

    case "$_SEL" in
        reality) ENABLE_REALITY=false ;;
        hy2)     ENABLE_HY2=false ;;
        socks5)  ENABLE_SOCKS5=false ;;
        vmess)   ENABLE_VMESS=false ;;
        tuic)    ENABLE_TUIC=false ;;
    esac

    detect_main_ip
    write_config
    if ! "$BIN" check -c "$CFG_FILE" 2>&1; then
        echo -e "${RED}Config invalid.${NC}"; return
    fi

    write_info
    systemctl restart sing-box
    sleep 1
    echo -e "${GREEN}✓ ${_LABEL} removed and service restarted.${NC}"
    show_info
}

# ── Update binary ──────────────────────────────────────────────────────────────

do_update() {
    header
    echo -e "${YELLOW}▶ Checking for updates...${NC}"
    local LATEST LATEST_VER CURRENT ARCH URL
    LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    [[ -z "$LATEST" ]] && echo -e "${RED}Failed to fetch version info.${NC}" && return
    LATEST_VER=${LATEST#v}
    CURRENT=$("$BIN" version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)

    if [[ "$CURRENT" == "$LATEST_VER" ]]; then
        echo -e "${GREEN}Already on latest: ${CURRENT}${NC}"
        return
    fi

    echo -e "Updating ${RED}${CURRENT}${NC} → ${GREEN}${LATEST_VER}${NC}"
    ARCH=$(uname -m); [[ "$ARCH" == "aarch64" ]] && ARCH="arm64" || ARCH="amd64"
    URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${LATEST_VER}-linux-${ARCH}.tar.gz"

    curl -sL "$URL" -o /tmp/sb.tar.gz \
        || { echo -e "${RED}Download failed.${NC}"; return; }
    tar -xzf /tmp/sb.tar.gz -C /tmp/ \
        || { echo -e "${RED}Extract failed.${NC}"; rm -f /tmp/sb.tar.gz; return; }

    cp "$BIN" "${BIN}.bak" 2>/dev/null
    systemctl stop sing-box

    if mv /tmp/sing-box-${LATEST_VER}-linux-${ARCH}/sing-box "$BIN"; then
        chmod +x "$BIN"
        rm -f "${BIN}.bak" /tmp/sb.tar.gz
        rm -rf /tmp/sing-box-${LATEST_VER}-linux-${ARCH}
        systemctl start sing-box
        echo -e "${GREEN}✓ Updated to $($BIN version | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)${NC}"
    else
        mv "${BIN}.bak" "$BIN" 2>/dev/null
        rm -f /tmp/sb.tar.gz
        rm -rf /tmp/sing-box-${LATEST_VER}-linux-${ARCH}
        systemctl start sing-box
        echo -e "${RED}✗ Update failed — restored previous version.${NC}"
    fi
}

# ── BBR ───────────────────────────────────────────────────────────────────────

do_bbr() {
    header
    echo -e " ${BOLD}BBR Congestion Control${NC}"
    echo ""

    local CC QDISC
    CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    if [[ "$CC" == "bbr" ]]; then
        echo -e "  Status    : ${GREEN}● enabled${NC}"
        printf "  %-10s ${GREEN}%s${NC}\n" "Qdisc:"   "$QDISC"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Disable BBR  (revert to cubic)"
    else
        echo -e "  Status    : ${YELLOW}● disabled${NC}"
        printf "  %-10s ${YELLOW}%s${NC}\n" "Current:" "$CC"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Enable BBR"
    fi
    echo -e "  ${RED}0.${NC}  Back"
    echo ""
    read -rp "$(echo -e "${YELLOW}Choice: ${NC}")" BBR_OPT

    case "$BBR_OPT" in
        0) return ;;
        1)
            if [[ "$CC" == "bbr" ]]; then
                confirm "Disable BBR and revert to cubic?" || return
                sysctl -w net.ipv4.tcp_congestion_control=cubic  >/dev/null
                sysctl -w net.core.default_qdisc=pfifo_fast      >/dev/null
                rm -f /etc/sysctl.d/99-bbr.conf
                echo -e "${GREEN}✓ BBR disabled. Reverted to cubic.${NC}"
            else
                modprobe tcp_bbr 2>/dev/null
                if ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
                    echo -e "${RED}✗ BBR is not supported by this kernel.${NC}"
                    return
                fi
                sysctl -w net.core.default_qdisc=fq          >/dev/null
                sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null
                cat > /etc/sysctl.d/99-bbr.conf << 'SYSCTL'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL
                echo -e "${GREEN}✓ BBR enabled and set persistent.${NC}"
            fi ;;
        *) echo -e "${RED}Invalid.${NC}" ;;
    esac
}

# ── VPS Tools ─────────────────────────────────────────────────────────────────

vps_check_ip() {
    echo -e "${YELLOW}▶ Fetching IP info...${NC}"
    local DATA IP COUNTRY REGION CITY ISP ORG AS PROXY HOSTING MOBILE
    DATA=$(curl -s --max-time 10 \
        "http://ip-api.com/json?fields=status,country,regionName,city,isp,org,as,proxy,hosting,mobile,query" \
        2>/dev/null)
    [[ -z "$DATA" ]] && echo -e "${RED}Failed to fetch IP info.${NC}" && return

    IP=$(echo      "$DATA" | grep -oP '"query"\s*:\s*"\K[^"]+')
    COUNTRY=$(echo "$DATA" | grep -oP '"country"\s*:\s*"\K[^"]+')
    REGION=$(echo  "$DATA" | grep -oP '"regionName"\s*:\s*"\K[^"]+')
    CITY=$(echo    "$DATA" | grep -oP '"city"\s*:\s*"\K[^"]+')
    ISP=$(echo     "$DATA" | grep -oP '"isp"\s*:\s*"\K[^"]+')
    ORG=$(echo     "$DATA" | grep -oP '"org"\s*:\s*"\K[^"]+')
    AS=$(echo      "$DATA" | grep -oP '"as"\s*:\s*"\K[^"]+')
    PROXY=$(echo   "$DATA" | grep -oP '"proxy"\s*:\s*\K(true|false)')
    HOSTING=$(echo "$DATA" | grep -oP '"hosting"\s*:\s*\K(true|false)')
    MOBILE=$(echo  "$DATA" | grep -oP '"mobile"\s*:\s*\K(true|false)')

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    printf "  %-12s ${GREEN}%s${NC}\n" "IP:"       "$IP"
    printf "  %-12s ${GREEN}%s, %s, %s${NC}\n" "Location:" "$CITY" "$REGION" "$COUNTRY"
    printf "  %-12s ${GREEN}%s${NC}\n" "ISP:"      "$ISP"
    printf "  %-12s ${GREEN}%s${NC}\n" "Org:"      "$ORG"
    printf "  %-12s ${GREEN}%s${NC}\n" "AS:"       "$AS"
    echo ""
    [[ "$PROXY"   == "true" ]] \
        && printf "  %-12s ${RED}● yes${NC}\n"    "Proxy/VPN:" \
        || printf "  %-12s ${GREEN}● no${NC}\n"   "Proxy/VPN:"
    [[ "$HOSTING" == "true" ]] \
        && printf "  %-12s ${YELLOW}● yes${NC}\n" "Hosting:"   \
        || printf "  %-12s ${GREEN}● no${NC}\n"   "Hosting:"
    [[ "$MOBILE"  == "true" ]] \
        && printf "  %-12s ${YELLOW}● yes${NC}\n" "Mobile:"    \
        || printf "  %-12s ${GREEN}● no${NC}\n"   "Mobile:"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
}

vps_speedtest() {
    echo -e "${YELLOW}▶ Testing download speed...${NC}"
    echo ""

    local -a _URLS _LABELS
    _URLS=(
        "https://speed.cloudflare.com/__down?bytes=104857600"
        "https://speedtest.tele2.net/100MB.zip"
        "https://speed.hetzner.de/100MB.bin"
        "https://lg-sin.vultr.com/100MB.bin"
    )
    _LABELS=(
        "Cloudflare    (Global)"
        "Tele2         (Europe)"
        "Hetzner       (Germany)"
        "Vultr         (Singapore)"
    )

    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    for i in "${!_URLS[@]}"; do
        local _BYTES _MBPS
        printf "  %-26s " "${_LABELS[$i]}"
        _BYTES=$(curl -o /dev/null -s --max-time 20 -w "%{speed_download}" "${_URLS[$i]}" 2>/dev/null)
        _MBPS=$(awk "BEGIN {printf \"%.2f\", ${_BYTES:-0}/1048576}")
        echo -e "${GREEN}${_MBPS} MB/s${NC}"
    done
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    echo ""

    if command -v speedtest-cli &>/dev/null; then
        confirm "Run speedtest-cli for upload speed too?" && echo "" && speedtest-cli --simple
    elif command -v speedtest &>/dev/null; then
        confirm "Run Ookla speedtest for upload speed too?" && echo "" && speedtest
    else
        echo -e "  ${CYAN}Tip: install speedtest-cli for upload testing${NC}"
        echo -e "  ${CYAN}     pip3 install speedtest-cli${NC}"
    fi
}

vps_check_dns() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e " ${BOLD}Current DNS Servers:${NC}"
    echo ""
    grep "^nameserver" /etc/resolv.conf 2>/dev/null | while read -r _ ip; do
        printf "  ${GREEN}%s${NC}\n" "$ip"
    done
    echo ""
    echo -e " ${BOLD}Resolution Test:${NC}"
    echo ""
    for _dom in google.com cloudflare.com github.com; do
        local _RES
        _RES=$(getent hosts "$_dom" 2>/dev/null | awk '{print $1; exit}')
        if [[ -n "$_RES" ]]; then
            printf "  %-22s ${GREEN}%s${NC}\n" "$_dom" "$_RES"
        else
            printf "  %-22s ${RED}failed${NC}\n" "$_dom"
        fi
    done
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
}

vps_change_dns() {
    header
    echo -e " ${BOLD}Change DNS${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC}  Google        ${CYAN}8.8.8.8 / 8.8.4.4${NC}"
    echo -e "  ${GREEN}2.${NC}  Cloudflare    ${CYAN}1.1.1.1 / 1.0.0.1${NC}"
    echo -e "  ${GREEN}3.${NC}  OpenDNS       ${CYAN}208.67.222.222 / 208.67.220.220${NC}"
    echo -e "  ${GREEN}4.${NC}  Quad9         ${CYAN}9.9.9.9 / 149.112.112.112${NC}"
    echo -e "  ${GREEN}5.${NC}  AdGuard       ${CYAN}94.140.14.14 / 94.140.15.15${NC}"
    echo -e "  ${GREEN}6.${NC}  Comodo        ${CYAN}8.26.56.26 / 8.20.247.20${NC}"
    echo -e "  ${GREEN}7.${NC}  Custom"
    echo -e "  ${RED}0.${NC}  Back"
    echo ""
    read -rp "$(echo -e "${YELLOW}Choice: ${NC}")" _DC

    local _D1 _D2
    case "$_DC" in
        0) return ;;
        1) _D1="8.8.8.8";        _D2="8.8.4.4" ;;
        2) _D1="1.1.1.1";        _D2="1.0.0.1" ;;
        3) _D1="208.67.222.222"; _D2="208.67.220.220" ;;
        4) _D1="9.9.9.9";        _D2="149.112.112.112" ;;
        5) _D1="94.140.14.14";   _D2="94.140.15.15" ;;
        6) _D1="8.26.56.26";     _D2="8.20.247.20" ;;
        7)
            read -rp "$(echo -e "${YELLOW}Primary DNS:   ${NC}")" _D1
            read -rp "$(echo -e "${YELLOW}Secondary DNS: ${NC}")" _D2
            [[ -z "$_D1" ]] && echo -e "${RED}Primary DNS cannot be empty.${NC}" && return
            ;;
        *) echo -e "${RED}Invalid.${NC}"; return ;;
    esac

    # Back up existing resolv.conf (follow symlink so we preserve content)
    cp -L /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null

    # On Ubuntu/Debian with systemd-resolved, /etc/resolv.conf is a symlink —
    # remove it so we can write a real file
    [[ -L /etc/resolv.conf ]] && rm /etc/resolv.conf

    # Remove immutable flag if set
    chattr -i /etc/resolv.conf 2>/dev/null

    cat > /etc/resolv.conf << EOF
nameserver ${_D1}
nameserver ${_D2}
EOF

    echo -e "${GREEN}✓ DNS set to ${_D1} / ${_D2}${NC}"
    echo -e "  ${CYAN}Backup saved to /etc/resolv.conf.bak${NC}"
    echo ""
    echo -e "${YELLOW}▶ Testing new DNS...${NC}"
    if getent hosts google.com >/dev/null 2>&1; then
        echo -e "${GREEN}✓ DNS resolution working.${NC}"
    else
        echo -e "${RED}✗ Resolution failed — restoring backup.${NC}"
        cp /etc/resolv.conf.bak /etc/resolv.conf
    fi
}

vps_ip_quality() {
    echo -e "${YELLOW}▶ Checking IP quality...${NC}"
    local _IP _DATA _PROXY _HOSTING _MOBILE _ISP _ORG _AS _COUNTRY _CC
    _IP=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null)
    [[ -z "$_IP" ]] && _IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
    [[ -z "$_IP" ]] && echo -e "${RED}Failed to detect IP.${NC}" && return

    _DATA=$(curl -s --max-time 10 \
        "http://ip-api.com/json/${_IP}?fields=status,country,countryCode,isp,org,as,proxy,hosting,mobile,query" \
        2>/dev/null)
    [[ -z "$_DATA" ]] && echo -e "${RED}Failed to query IP info.${NC}" && return

    _PROXY=$(echo   "$_DATA" | grep -oP '"proxy"\s*:\s*\K(true|false)')
    _HOSTING=$(echo "$_DATA" | grep -oP '"hosting"\s*:\s*\K(true|false)')
    _MOBILE=$(echo  "$_DATA" | grep -oP '"mobile"\s*:\s*\K(true|false)')
    _ISP=$(echo     "$_DATA" | grep -oP '"isp"\s*:\s*"\K[^"]+')
    _ORG=$(echo     "$_DATA" | grep -oP '"org"\s*:\s*"\K[^"]+')
    _AS=$(echo      "$_DATA" | grep -oP '"as"\s*:\s*"\K[^"]+')
    _COUNTRY=$(echo "$_DATA" | grep -oP '"country"\s*:\s*"\K[^"]+')
    _CC=$(echo      "$_DATA" | grep -oP '"countryCode"\s*:\s*"\K[^"]+')

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e " ${BOLD}IP Quality — ${_IP}${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    printf "  %-14s ${GREEN}%s (%s)${NC}\n" "Country:"  "$_COUNTRY" "$_CC"
    printf "  %-14s ${GREEN}%s${NC}\n"       "ISP:"     "$_ISP"
    printf "  %-14s ${GREEN}%s${NC}\n"       "Org:"     "$_ORG"
    printf "  %-14s ${GREEN}%s${NC}\n"       "AS:"      "$_AS"
    echo ""
    [[ "$_PROXY"   == "true" ]] \
        && printf "  %-14s ${RED}● flagged as proxy / VPN${NC}\n"   "Proxy/VPN:" \
        || printf "  %-14s ${GREEN}● clean${NC}\n"                   "Proxy/VPN:"
    [[ "$_HOSTING" == "true" ]] \
        && printf "  %-14s ${YELLOW}● datacenter / hosting IP${NC}\n" "Hosting:"  \
        || printf "  %-14s ${GREEN}● clean${NC}\n"                    "Hosting:"
    [[ "$_MOBILE"  == "true" ]] \
        && printf "  %-14s ${YELLOW}● yes${NC}\n" "Mobile:"           \
        || printf "  %-14s ${GREEN}● no${NC}\n"   "Mobile:"

    # Risk summary
    echo ""
    local _RISK=0
    [[ "$_PROXY"   == "true" ]] && ((_RISK++))
    [[ "$_HOSTING" == "true" ]] && ((_RISK++))
    if (( _RISK == 0 )); then
        echo -e "  ${GREEN}✓ No risk flags detected.${NC}"
    elif (( _RISK == 1 )); then
        echo -e "  ${YELLOW}⚠ 1 risk flag detected.${NC}"
    else
        echo -e "  ${RED}✗ ${_RISK} risk flags detected.${NC}"
    fi
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
}

vps_node_quality() {
    echo -e "${YELLOW}▶ Running Node Quality check...${NC}"
    echo -e "  ${CYAN}Press Ctrl+C to abort.${NC}"
    echo ""
    bash <(curl -sL https://run.NodeQuality.com)
}

vps_yabs() {
    echo -e "${YELLOW}▶ Starting YABS benchmark...${NC}"
    echo -e "  ${CYAN}Includes: disk I/O, CPU, and network speed tests.${NC}"
    echo -e "  ${CYAN}May take 5–15 minutes. Press Ctrl+C to abort.${NC}"
    echo ""
    local _T0 _T1 _ELAPSED
    _T0=$(date +%s)
    bash <(curl -sL yabs.sh)
    _T1=$(date +%s)
    _ELAPSED=$(( _T1 - _T0 ))
    echo ""
    printf "  ${CYAN}Completed in %dm %ds${NC}\n" $((_ELAPSED/60)) $((_ELAPSED%60))
}

do_vps_tools() {
    while true; do
        header
        echo -e " ${BOLD}VPS Tools${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Check IP Info"
        echo -e "  ${GREEN}2.${NC}  Speed Test"
        echo -e "  ${GREEN}3.${NC}  Check DNS"
        echo -e "  ${GREEN}4.${NC}  Change DNS"
        echo -e "  ${GREEN}5.${NC}  IP Quality Check"
        echo -e "  ${GREEN}6.${NC}  Run YABS Benchmark"
        echo -e "  ${GREEN}7.${NC}  Node Quality Check"
        echo ""
        echo -e "  ${RED}0.${NC}  Back"
        echo ""
        read -rp "$(echo -e "${YELLOW}Choice [0-7]: ${NC}")" _VT

        case "$_VT" in
            1) header; vps_check_ip;      pause ;;
            2) header; vps_speedtest;     pause ;;
            3) header; vps_check_dns;     pause ;;
            4) vps_change_dns;            pause ;;
            5) header; vps_ip_quality;    pause ;;
            6) header; vps_yabs;          pause ;;
            7) header; vps_node_quality;  pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid.${NC}"; sleep 1 ;;
        esac
    done
}

# ── Uninstall ──────────────────────────────────────────────────────────────────

do_uninstall() {
    header
    echo -e "${RED}This will completely remove sing-box.${NC}"
    confirm "Continue?" || { echo "Cancelled."; return; }
    systemctl stop    sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    rm -f "$SERVICE" "$BIN"
    rm -rf "$CFG_DIR"
    systemctl daemon-reload
    echo -e "${GREEN}✓ Uninstalled.${NC}"
}

# ── Shortcut ───────────────────────────────────────────────────────────────────

install_shortcut() {
    [[ -x "$SHORTCUT" ]] && return
    cat > "$SHORTCUT" << 'EOF'
#!/bin/bash
bash <(curl -sL https://raw.githubusercontent.com/SatkiExE808/vless-reality-setup/main/setup.sh)
EOF
    chmod +x "$SHORTCUT"
    echo -e "${GREEN}✓ Shortcut installed — type ${BOLD}sb${NC}${GREEN} anywhere to reopen this manager${NC}"
    echo ""
}

# ── Main menu ──────────────────────────────────────────────────────────────────

main_menu() {
    install_shortcut
    while true; do
        header

        if is_installed; then
            local SB_STATUS SB_VER
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
            echo -e "  ${GREEN}2.${NC} Add Protocol"
            echo -e "  ${GREEN}3.${NC} Remove Protocol"
            echo -e "  ${GREEN}4.${NC} Restart Service"
            echo -e "  ${GREEN}5.${NC} Stop / Start Service"
            echo -e "  ${GREEN}6.${NC} View Logs"
            echo -e "  ${GREEN}7.${NC} Update sing-box"
            echo -e "  ${GREEN}8.${NC} BBR Enable / Disable"
            echo -e "  ${GREEN}9.${NC} VPS Tools"
            echo -e "  ${GREEN}10.${NC} Reinstall"
            echo -e "  ${RED}11.${NC} Uninstall"
            echo ""
            echo -e "  ${RED}0.${NC} Exit"
        fi

        echo ""
        read -rp "$(echo -e "${YELLOW}Select [0-11]: ${NC}")" OPT

        case "$OPT" in
            1)
                if is_installed; then show_info; else do_install; fi
                pause ;;
            2) do_add_protocol;    pause ;;
            3) do_delete_protocol; pause ;;
            4)
                systemctl restart sing-box \
                    && echo -e "${GREEN}✓ Restarted.${NC}" \
                    || echo -e "${RED}✗ Failed.${NC}"
                pause ;;
            5)
                if [[ "$(systemctl is-active sing-box 2>/dev/null)" == "active" ]]; then
                    systemctl stop  sing-box && echo -e "${YELLOW}● Stopped.${NC}"
                else
                    systemctl start sing-box && echo -e "${GREEN}● Started.${NC}"
                fi
                pause ;;
            6)
                journalctl -u sing-box -n 60 --no-pager
                pause ;;
            7) do_update;          pause ;;
            8) do_bbr;             pause ;;
            9) do_vps_tools ;;
           10) do_uninstall; do_install; pause ;;
           11) do_uninstall; pause ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
