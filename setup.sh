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
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}    ${RED}${BOLD}V${NC} ${YELLOW}${BOLD}P${NC} ${GREEN}${BOLD}S${NC}   ${CYAN}${BOLD}T${NC} ${BLUE}${BOLD}O${NC} ${PURPLE}${BOLD}O${NC} ${RED}${BOLD}L${NC} ${YELLOW}${BOLD}B${NC} ${GREEN}${BOLD}O${NC} ${CYAN}${BOLD}X${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

_menu_sep()  { echo -e "  ${CYAN}────────────────────────────────────────────────────${NC}"; }
_menu_hdr() {
    local _n=$(( 46 - ${#1} )); (( _n < 1 )) && _n=1
    local _d='' _i; for (( _i=0; _i<_n; _i++ )); do _d+='─'; done
    echo -e "  ${CYAN}──── ${BOLD}$1${NC}${CYAN} ${_d}${NC}"
}
_menu_item() { printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %s\n" "$1" "$2"; }
_menu_quit() { printf "  ${RED}%3s${NC}  ${CYAN}›${NC}  %s\n" "$1" "$2"; }

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
            if ss -tlnp 2>/dev/null | grep -q ":${_pt}\b" || \
               ss -ulnp 2>/dev/null | grep -q ":${_pt}\b"; then
                echo -e "${YELLOW}  ⚠ Port ${_pt} appears to be in use. Use anyway? [y/N]: ${NC}"
                read -r _force
                [[ ! "$_force" =~ ^[Yy]$ ]] && continue
            fi
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
        echo -e "  ${BOLD}${GREEN}◆ VLESS Reality${NC}"
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
        echo -e "  ${BOLD}${PURPLE}◆ Hysteria2${NC}"
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
        echo -e "  ${BOLD}${YELLOW}◆ VMess + WebSocket${NC}"
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
        echo -e "  ${BOLD}${PURPLE}◆ TUIC v5${NC}"
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
        echo -e "  ${BOLD}${BLUE}◆ SOCKS5${NC}"
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
    echo -e "  ${BOLD}Install Protocol${NC}"
    echo ""
    _menu_sep
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  1  "VLESS Reality"       "TCP · most secure"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  2  "Hysteria2"           "UDP · fast"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  3  "VMess + WebSocket"   "TCP · compatible"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  4  "TUIC"                "UDP · fast · QUIC"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  5  "SOCKS5"              "TCP · simple"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %s\n"                    6  "All protocols"
    _menu_sep
    echo ""
    read -rp "$(echo -e "${YELLOW}  Select [1-6, default 1]: ${NC}")" PC
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
        echo -e "${GREEN}✓ Service started successfully${NC}"
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
    echo -e "  ${BOLD}Add Protocol${NC}"
    echo ""

    # Active protocols
    local ANY_ACTIVE=false
    [[ $ENABLE_REALITY == true ]] && echo -e "  ${GREEN}✓${NC}  VLESS Reality"     && ANY_ACTIVE=true
    [[ $ENABLE_HY2     == true ]] && echo -e "  ${GREEN}✓${NC}  Hysteria2"         && ANY_ACTIVE=true
    [[ $ENABLE_VMESS   == true ]] && echo -e "  ${GREEN}✓${NC}  VMess + WebSocket" && ANY_ACTIVE=true
    [[ $ENABLE_TUIC    == true ]] && echo -e "  ${GREEN}✓${NC}  TUIC"              && ANY_ACTIVE=true
    [[ $ENABLE_SOCKS5  == true ]] && echo -e "  ${GREEN}✓${NC}  SOCKS5"            && ANY_ACTIVE=true
    [[ $ANY_ACTIVE == true ]] && echo ""

    # Available to add
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

    _menu_sep
    for i in "${!_NAMES[@]}"; do
        printf "  ${GREEN}%3d${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n" \
            $((i+1)) "${_NAMES[$i]}" "${_DESCS[$i]}"
    done
    _menu_sep
    _menu_quit  0  "Back"

    echo ""
    read -rp "$(echo -e "${YELLOW}  Select: ${NC}")" ADD_CHOICE

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
    systemctl is-active --quiet sing-box \
        && echo -e "${GREEN}✓ Service restarted.${NC}" \
        || echo -e "${RED}✗ Service failed to start — check: journalctl -u sing-box -n 20${NC}"
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
    echo -e "  ${BOLD}Remove Protocol${NC}"
    echo ""
    _menu_sep
    for i in "${!_NAMES[@]}"; do
        _menu_item $((i+1)) "${_NAMES[$i]}"
    done
    _menu_sep
    echo ""
    _menu_quit  0  "Back"
    echo ""
    read -rp "$(echo -e "${YELLOW}  Select: ${NC}")" DEL_CHOICE

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
    systemctl is-active --quiet sing-box \
        && echo -e "${GREEN}✓ Service restarted.${NC}" \
        || echo -e "${RED}✗ Service failed to start — check: journalctl -u sing-box -n 20${NC}"
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
    echo -e "  ${BOLD}BBR Congestion Control${NC}"
    echo ""

    local CC QDISC
    CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    if [[ "$CC" == "bbr" ]]; then
        printf "  %-10s ${GREEN}● enabled${NC}\n"  "Status :"
        printf "  %-10s ${GREEN}%s${NC}\n"          "Qdisc  :" "$QDISC"
        echo ""
        _menu_sep
        _menu_item  1  "Disable BBR  (revert to cubic)"
    else
        printf "  %-10s ${YELLOW}● disabled${NC}\n" "Status :"
        printf "  %-10s ${YELLOW}%s${NC}\n"          "Current:" "$CC"
        echo ""
        _menu_sep
        _menu_item  1  "Enable BBR"
    fi
    _menu_sep
    echo ""
    _menu_quit  0  "Back"
    echo ""
    read -rp "$(echo -e "${YELLOW}  Select: ${NC}")" BBR_OPT

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

# ── VPS Toolbox ─────────────────────────────────────────────────────────────────

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

    # Auto-install speedtest-cli if not present
    if ! command -v speedtest-cli &>/dev/null && ! command -v speedtest &>/dev/null; then
        echo -e "${YELLOW}▶ Installing speedtest-cli...${NC}"
        if apt-get install -y -qq speedtest-cli 2>/dev/null; then
            echo -e "${GREEN}✓ Installed via apt${NC}"
        elif command -v pip3 &>/dev/null && pip3 install speedtest-cli -q 2>/dev/null; then
            echo -e "${GREEN}✓ Installed via pip3${NC}"
        else
            echo -e "${RED}✗ Could not install speedtest-cli.${NC}"
            return
        fi
        echo ""
    fi

    echo -e "${YELLOW}▶ Running full speedtest (download + upload)...${NC}"
    echo ""
    if command -v speedtest-cli &>/dev/null; then
        speedtest-cli --simple
    else
        speedtest
    fi
}

dns_provider() {
    case "$1" in
        8.8.8.8|8.8.4.4)                 echo "Google" ;;
        1.1.1.1|1.0.0.1)                 echo "Cloudflare" ;;
        208.67.222.222|208.67.220.220)   echo "OpenDNS" ;;
        9.9.9.9|149.112.112.112)         echo "Quad9" ;;
        94.140.14.14|94.140.15.15)       echo "AdGuard" ;;
        8.26.56.26|8.20.247.20)          echo "Comodo" ;;
        185.228.168.9|185.228.169.9)     echo "CleanBrowsing" ;;
        77.88.8.8|77.88.8.1)            echo "Yandex" ;;
        76.76.19.19|76.223.122.150)      echo "Alternate DNS" ;;
        127.0.0.53)                       echo "systemd-resolved (local stub)" ;;
        127.0.0.1)                        echo "localhost" ;;
        *)
            local _ORG
            _ORG=$(curl -s --max-time 5 \
                "http://ip-api.com/json/${1}?fields=org,isp" 2>/dev/null \
                | grep -oP '"org"\s*:\s*"\K[^"]+')
            echo "${_ORG:-Unknown}"
            ;;
    esac
}

vps_check_dns() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Current DNS Servers:${NC}"
    echo ""
    while read -r _ ip; do
        local _PROV
        _PROV=$(dns_provider "$ip")
        printf "  ${GREEN}%-18s${NC} ${CYAN}%s${NC}\n" "$ip" "$_PROV"
    done < <(grep "^nameserver" /etc/resolv.conf 2>/dev/null)
    echo ""
    echo -e "  ${BOLD}Resolution Test:${NC}"
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
    echo -e "  ${BOLD}Change DNS${NC}"
    echo ""
    _menu_sep
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-14s ${CYAN}%s${NC}\n"  1  "Google"      "8.8.8.8 / 8.8.4.4"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-14s ${CYAN}%s${NC}\n"  2  "Cloudflare"  "1.1.1.1 / 1.0.0.1"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-14s ${CYAN}%s${NC}\n"  3  "OpenDNS"     "208.67.222.222 / 208.67.220.220"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-14s ${CYAN}%s${NC}\n"  4  "Quad9"       "9.9.9.9 / 149.112.112.112"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-14s ${CYAN}%s${NC}\n"  5  "AdGuard"     "94.140.14.14 / 94.140.15.15"
    printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-14s ${CYAN}%s${NC}\n"  6  "Comodo"      "8.26.56.26 / 8.20.247.20"
    _menu_item  7  "Custom"
    _menu_sep
    echo ""
    _menu_quit  0  "Back"
    echo ""
    read -rp "$(echo -e "${YELLOW}  Select: ${NC}")" _DC

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
            read -rp "$(echo -e "${YELLOW}Secondary DNS (optional): ${NC}")" _D2
            [[ -z "$_D1" ]] && echo -e "${RED}Primary DNS cannot be empty.${NC}" && return
            ;;
        *) echo -e "${RED}Invalid.${NC}"; return ;;
    esac

    echo ""
    [[ -z "$_D2" ]] && _D2="$_D1"   # ensure secondary is never empty before any writes

    local _RESOLV="/etc/resolv.conf"
    local _methods=""

    # ── 0. Tailscale ─────────────────────────────────────────────────
    # Tailscale writes /etc/resolv.conf directly and overwrites everything.
    # Must stop it before touching the file, then restart after protecting it.
    local _ts_was_running=0
    if systemctl is-active --quiet tailscaled 2>/dev/null; then
        _ts_was_running=1
        tailscale set --accept-dns=false 2>/dev/null || true
        systemctl stop tailscaled 2>/dev/null
        _methods+=" tailscale(stopped)"
    fi

    # ── 1. systemd-resolved ──────────────────────────────────────────
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        mkdir -p /etc/systemd/resolved.conf.d
        printf "[Resolve]\nDNS=%s %s\n" "$_D1" "$_D2" \
            > /etc/systemd/resolved.conf.d/custom-dns.conf
        local _IF
        _IF=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+')
        if [[ -n "$_IF" ]]; then
            resolvectl dns    "$_IF" "$_D1" "$_D2" 2>/dev/null
            resolvectl domain "$_IF" "~."           2>/dev/null
        fi
        systemctl restart systemd-resolved 2>/dev/null || true
        _methods+=" systemd-resolved"
    fi

    # ── 2. NetworkManager ────────────────────────────────────────────
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        mkdir -p /etc/NetworkManager/conf.d
        printf "[main]\ndns=none\n" > /etc/NetworkManager/conf.d/no-dns-override.conf
        systemctl reload NetworkManager 2>/dev/null || true
        _methods+=" NetworkManager"
    fi

    # ── 3. resolvconf package ────────────────────────────────────────
    if command -v resolvconf &>/dev/null; then
        mkdir -p /etc/resolvconf/resolv.conf.d
        printf "nameserver %s\nnameserver %s\n" "$_D1" "$_D2" \
            > /etc/resolvconf/resolv.conf.d/head
        resolvconf -u 2>/dev/null || true
        _methods+=" resolvconf"
    fi

    # ── 4. dhclient hook ─────────────────────────────────────────────
    if [[ -d /etc/dhcp ]]; then
        mkdir -p /etc/dhcp/dhclient-enter-hooks.d
        printf '#!/bin/sh\nmake_resolv_conf() { : ; }\n' \
            > /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate
        chmod +x /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate
    fi

    # ── 5. Direct /etc/resolv.conf write ────────────────────────────
    cp -L "$_RESOLV" "${_RESOLV}.bak" 2>/dev/null || true
    [[ -L "$_RESOLV" ]] && rm -f "$_RESOLV"   # remove symlink BEFORE chattr
    chattr -i "$_RESOLV" 2>/dev/null || true   # now safe: operates on plain file
    printf "nameserver %s\nnameserver %s\n" "$_D1" "$_D2" > "$_RESOLV"
    chattr +i "$_RESOLV" 2>/dev/null || true   # protect — Tailscale/dhclient can't overwrite
    _methods+=" resolv.conf(+i)"

    # ── Restart Tailscale (now it can't overwrite the protected file) ─
    if [[ "$_ts_was_running" -eq 1 ]]; then
        systemctl start tailscaled 2>/dev/null || true
        _methods+=" →restarted"
    fi

    echo -e "${GREEN}✓ DNS changed to ${_D1} / ${_D2}${NC}"
    echo -e "  ${CYAN}Methods applied:${_methods}${NC}"
    echo -e "  ${CYAN}Backup: ${_RESOLV}.bak${NC}"
    echo ""

    # ── 6. Verify ────────────────────────────────────────────────────
    echo -e "${YELLOW}▶ Testing DNS resolution...${NC}"
    sleep 1  # give systemd-resolved a moment to finish restarting
    local _ok=0
    if command -v dig &>/dev/null; then
        dig +short +time=5 "@$_D1" google.com A &>/dev/null && _ok=1
    elif command -v nslookup &>/dev/null; then
        nslookup google.com "$_D1" &>/dev/null && _ok=1
    else
        getent ahosts google.com &>/dev/null && _ok=1
    fi
    if [[ "$_ok" -eq 1 ]]; then
        echo -e "${GREEN}✓ DNS resolution working.${NC}"
    else
        echo -e "${YELLOW}⚠ Direct query to ${_D1} failed — the DNS may still work${NC}"
        echo -e "  ${CYAN}Test manually: cat /etc/resolv.conf${NC}"
        [[ -n "$(command -v resolvectl)" ]] && \
            echo -e "  ${CYAN}                resolvectl status${NC}"
    fi
}


vps_system_update() {
    echo -e "${YELLOW}▶ Checking for system updates...${NC}"
    echo ""
    apt-get update -qq 2>/dev/null
    local UPGRADABLE
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l)

    if [[ "$UPGRADABLE" -eq 0 ]]; then
        echo -e "${GREEN}✓ System is up to date.${NC}"
        return
    fi

    echo -e "  ${YELLOW}${UPGRADABLE} package(s) can be upgraded:${NC}"
    echo ""
    apt list --upgradable 2>/dev/null | grep -v "^Listing" | while read -r pkg; do
        echo -e "  ${CYAN}·${NC} $pkg"
    done
    echo ""
    if confirm "Install all updates now?"; then
        echo ""
        apt-get upgrade -y
        echo ""
        echo -e "${GREEN}✓ System updated.${NC}"
    fi
}

vps_node_quality() {
    echo -e "${YELLOW}▶ Running Node Quality check...${NC}"
    echo -e "  ${CYAN}Press Ctrl+C to abort.${NC}"
    echo ""
    bash <(curl -sL https://run.NodeQuality.com)
}

vps_fail2ban() {
    header
    echo -e "  ${BOLD}Fail2Ban${NC}"
    echo ""

    local _installed=0
    command -v fail2ban-client &>/dev/null && _installed=1

    if [[ "$_installed" -eq 1 ]]; then
        # ── Already installed: show status + manage ───────────────────
        local _status
        _status=$(systemctl is-active fail2ban 2>/dev/null)
        echo -e "  Status : $([ "$_status" = "active" ] && echo "${GREEN}● running${NC}" || echo "${RED}● stopped${NC}")"
        echo -e "  Version: $(fail2ban-client version 2>/dev/null | head -1)"
        echo ""

        if [[ "$_status" = "active" ]]; then
            echo -e "  ${CYAN}Jails active:${NC}"
            fail2ban-client status 2>/dev/null | grep "Jail list" | \
                sed 's/.*Jail list:\s*//' | tr ',' '\n' | \
                while read -r j; do
                    j="${j// /}"
                    [[ -z "$j" ]] && continue
                    local _banned
                    _banned=$(fail2ban-client status "$j" 2>/dev/null | \
                              grep "Currently banned" | grep -oP '\d+')
                    printf "    ${GREEN}%-20s${NC} banned: %s\n" "$j" "${_banned:-0}"
                done
            echo ""
            echo -e "  ${CYAN}Recent bans (last 10):${NC}"
            grep "Ban " /var/log/fail2ban.log 2>/dev/null | tail -10 | \
                awk '{print "   ", $5, $6, $7}' || echo "   (no log entries)"
        fi

        echo ""
        _menu_sep
        _menu_item  1  "Restart fail2ban"
        _menu_item  2  "Stop fail2ban"
        [[ "$_status" != "active" ]] && _menu_item  3  "Start fail2ban"
        _menu_quit  9  "Uninstall fail2ban"
        _menu_sep
        echo ""
        _menu_quit  0  "Back"
        echo ""
        read -rp "$(echo -e "${YELLOW}  Select: ${NC}")" _FC
        case "$_FC" in
            1) systemctl restart fail2ban && echo -e "${GREEN}✓ Restarted.${NC}" ;;
            2) systemctl stop    fail2ban && echo -e "${YELLOW}● Stopped.${NC}" ;;
            3) systemctl start   fail2ban && echo -e "${GREEN}✓ Started.${NC}" ;;
            9)
                confirm "Uninstall fail2ban?" || return
                systemctl stop    fail2ban 2>/dev/null
                systemctl disable fail2ban 2>/dev/null
                apt-get purge -y fail2ban 2>/dev/null
                echo -e "${GREEN}✓ Fail2ban removed.${NC}"
                ;;
            0) return ;;
        esac
        return
    fi

    # ── Not installed: install ────────────────────────────────────────
    echo -e "  fail2ban is ${RED}not installed${NC}."
    echo ""
    confirm "Install fail2ban now?" || return
    echo ""

    apt-get update -qq
    apt-get install -y fail2ban

    # Write a basic jail.local that protects SSH
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 5
EOF

    systemctl enable --now fail2ban
    sleep 1

    if systemctl is-active --quiet fail2ban; then
        echo ""
        echo -e "${GREEN}✓ fail2ban installed and running.${NC}"
        echo -e "  ${CYAN}SSH jail enabled — bans after 5 failed attempts (1h ban).${NC}"
        echo -e "  ${CYAN}Config: /etc/fail2ban/jail.local${NC}"
    else
        echo -e "${RED}✗ fail2ban installed but failed to start.${NC}"
        echo -e "  ${CYAN}Check: journalctl -u fail2ban${NC}"
    fi
}

vps_system_info() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}System Overview${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

    local _OS _KERNEL _ARCH _CPU _CORES _LOAD _UPTIME
    _OS=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
    _KERNEL=$(uname -r)
    _ARCH=$(uname -m)
    _CPU=$(grep -m1 "model name" /proc/cpuinfo | cut -d':' -f2 | sed 's/^[ \t]*//')
    _CORES=$(nproc)
    _LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
    _UPTIME=$(uptime -p 2>/dev/null | sed 's/up //')

    printf "  %-14s ${GREEN}%s${NC}\n"          "OS:"      "${_OS:-N/A}"
    printf "  %-14s ${GREEN}%s (%s)${NC}\n"     "Kernel:"  "$_KERNEL" "$_ARCH"
    printf "  %-14s ${GREEN}%s${NC}\n"          "CPU:"     "${_CPU:-N/A}"
    printf "  %-14s ${GREEN}%s core(s)${NC}\n"  "Cores:"   "$_CORES"
    printf "  %-14s ${GREEN}%s${NC}\n"          "Load Avg:" "$_LOAD"
    printf "  %-14s ${GREEN}%s${NC}\n"          "Uptime:"  "${_UPTIME:-N/A}"
    echo ""

    # Memory
    echo -e "  ${BOLD}Memory${NC}"
    local _MEM_LINE _MEM_TOTAL _MEM_USED _MEM_FREE _MEM_PCT
    _MEM_LINE=$(free -h | awk '/^Mem:/{print $2" "$3" "$7}')
    _MEM_TOTAL=$(echo "$_MEM_LINE" | awk '{print $1}')
    _MEM_USED=$(echo "$_MEM_LINE"  | awk '{print $2}')
    _MEM_FREE=$(echo "$_MEM_LINE"  | awk '{print $3}')
    _MEM_PCT=$(free | awk '/^Mem:/{printf "%.0f", $3/$2*100}')
    printf "    Total: ${GREEN}%s${NC}   Used: ${YELLOW}%s (%s%%)${NC}   Avail: ${GREEN}%s${NC}\n" \
        "$_MEM_TOTAL" "$_MEM_USED" "$_MEM_PCT" "$_MEM_FREE"

    # Swap
    local _SWAP_TOTAL _SWAP_USED
    _SWAP_TOTAL=$(free -h | awk '/^Swap:/{print $2}')
    _SWAP_USED=$(free  -h | awk '/^Swap:/{print $3}')
    [[ "$_SWAP_TOTAL" != "0B" ]] && \
        printf "    Swap:  ${GREEN}%s${NC}   Used: ${YELLOW}%s${NC}\n" "$_SWAP_TOTAL" "$_SWAP_USED"
    echo ""

    # Disk
    echo -e "  ${BOLD}Disk${NC}"
    df -h --output=source,size,used,avail,pcent,target 2>/dev/null | \
        awk 'NR==1 || /^\/dev/' | head -6 | while read -r line; do
            if [[ "$line" == Filesystem* ]]; then
                printf "    ${CYAN}%s${NC}\n" "$line"
            else
                printf "    %s\n" "$line"
            fi
        done
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
}

vps_check_ports() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Listening Ports${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo ""
    printf "  ${CYAN}%-6s %-8s %-22s %s${NC}\n" "PROTO" "PORT" "ADDRESS" "PROCESS"
    echo -e "  ${CYAN}──────────────────────────────────────────────────${NC}"
    ss -tulnp 2>/dev/null | awk 'NR>1 {
        split($5, a, ":");
        port = a[length(a)];
        addr = "";
        for (i=1; i<length(a); i++) {
            addr = (addr == "" ? "" : addr ":") a[i];
        }
        proc = "";
        for (i=7; i<=NF; i++) proc = proc " " $i;
        gsub(/.*"/, "", proc); gsub(/".*/, "", proc);
        printf "  %-6s %-8s %-22s %s\n", toupper($1), port, addr, proc
    }' | sort -k2 -n | head -30
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
}

do_vps_tools() {
    while true; do
        clear
        # ── Fancy header ─────────────────────────────────────────
        local _UP _LOAD _MEM_PCT
        _UP=$(uptime -p 2>/dev/null | sed 's/up //' | cut -c1-20)
        _LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
        _MEM_PCT=$(free 2>/dev/null | awk '/^Mem:/{printf "%.0f", $3/$2*100}')

        echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}${YELLOW}⚙  V P S   T O O L B O X${NC}                         ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════╣${NC}"
        printf "${CYAN}║${NC}  Uptime ${GREEN}%-15s${NC}  Load ${GREEN}%-5s${NC}  Mem ${YELLOW}%3s%%${NC}  ${CYAN}║${NC}\n" \
            "${_UP:-N/A}" "${_LOAD:-N/A}" "${_MEM_PCT:-?}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
        echo ""

        # ── Status chips ─────────────────────────────────────────
        local _CC _BBR_CHIP _F2B_CHIP
        _CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [[ "$_CC" == "bbr" ]]; then
            _BBR_CHIP="${GREEN}● BBR${NC}"
        else
            _BBR_CHIP="${YELLOW}○ BBR${NC}"
        fi
        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            _F2B_CHIP="${GREEN}● Fail2Ban${NC}"
        elif command -v fail2ban-client &>/dev/null; then
            _F2B_CHIP="${RED}○ Fail2Ban${NC}"
        else
            _F2B_CHIP="${PURPLE}◌ Fail2Ban${NC}"
        fi
        echo -e "  Active: ${_BBR_CHIP}   ${_F2B_CHIP}"
        echo ""

        # ── Menu ─────────────────────────────────────────────────
        _menu_hdr "Network"
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  1  "Check IP Info"        "geolocation · ASN · proxy flag"
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  2  "Speed Test"           "download + upload · global CDNs"
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  3  "Check DNS"            "current resolvers · test lookups"
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  4  "Change DNS"           "Cloudflare · Google · Quad9 · ..."
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  5  "Listening Ports"      "what's actually open"
        echo ""
        _menu_hdr "Diagnostics"
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  6  "System Info"          "CPU · RAM · disk · uptime"
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  7  "Node Quality Check"   "NodeQuality.com benchmark"
        echo ""
        _menu_hdr "Maintenance"
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  8  "System Update"        "apt update + upgrade"
        printf "  ${GREEN}%3s${NC}  ${CYAN}›${NC}  %-22s ${CYAN}%s${NC}\n"  9  "Fail2Ban"             "SSH brute-force protection"
        _menu_sep
        echo ""
        _menu_quit  0  "Back"
        echo ""
        read -rp "$(echo -e "${YELLOW}  Select: ${NC}")" _VT

        case "$_VT" in
            1)  header; vps_check_ip;       pause ;;
            2)  header; vps_speedtest;      pause ;;
            3)  header; vps_check_dns;      pause ;;
            4)  vps_change_dns;             pause ;;
            5)  header; vps_check_ports;    pause ;;
            6)  header; vps_system_info;    pause ;;
            7)  header; vps_node_quality;   pause ;;
            8)  header; vps_system_update;  pause ;;
            9)  vps_fail2ban;               pause ;;
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
    rm -f "$SHORTCUT"
    systemctl daemon-reload
    echo -e "${GREEN}✓ Fully uninstalled. Run the quick-start command to reinstall.${NC}"
}

# ── Shortcut ───────────────────────────────────────────────────────────────────

install_shortcut() {
    local _existed=0
    [[ -x "$SHORTCUT" ]] && _existed=1
    cat > "$SHORTCUT" << 'EOF'
#!/bin/bash
bash <(curl -sL https://raw.githubusercontent.com/SatkiExE808/vless-reality-setup/main/setup.sh)
EOF
    chmod +x "$SHORTCUT"
    [[ "$_existed" -eq 0 ]] && echo -e "${GREEN}✓ Shortcut installed — type ${BOLD}sb${NC}${GREEN} anywhere to reopen this manager${NC}" && echo ""
}

# ── Main menu ──────────────────────────────────────────────────────────────────

main_menu() {
    install_shortcut
    while true; do
        clear
        local _SB_STATUS _SB_VER
        if is_installed; then
            _SB_STATUS=$(systemctl is-active sing-box 2>/dev/null)
            _SB_VER=$("$BIN" version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)
        fi

        echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}    ${RED}${BOLD}V${NC} ${YELLOW}${BOLD}P${NC} ${GREEN}${BOLD}S${NC}   ${CYAN}${BOLD}T${NC} ${BLUE}${BOLD}O${NC} ${PURPLE}${BOLD}O${NC} ${RED}${BOLD}L${NC} ${YELLOW}${BOLD}B${NC} ${GREEN}${BOLD}O${NC} ${CYAN}${BOLD}X${NC}                         ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════╣${NC}"
        if is_installed; then
            local _ver_display="${_SB_VER:-?}"
            if [[ "$_SB_STATUS" == "active" ]]; then
                echo -e "${CYAN}║${NC}  Status  ${GREEN}● running${NC}      Version  ${GREEN}${_ver_display}${NC}$(printf '%*s' $((16 - ${#_ver_display})) '')${CYAN}║${NC}"
            else
                echo -e "${CYAN}║${NC}  Status  ${RED}● stopped${NC}      Version  ${_ver_display}$(printf '%*s' $((16 - ${#_ver_display})) '')${CYAN}║${NC}"
            fi
        else
            echo -e "${CYAN}║${NC}  Status  ${YELLOW}not installed${NC}                           ${CYAN}║${NC}"
        fi
        echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
        echo ""

        if ! is_installed; then
            _menu_hdr "Proxy"
            _menu_item  1  "Install sing-box"
            echo ""
            _menu_hdr "System"
            _menu_item  8  "BBR Enable / Disable"
            _menu_item  9  "VPS Toolbox"
            _menu_sep
            echo ""
            _menu_quit  0  "Exit"
        else
            _menu_hdr "Proxy"
            _menu_item  1  "Show Config & Links"
            _menu_item  2  "Add Protocol"
            _menu_item  3  "Remove Protocol"
            echo ""
            _menu_hdr "Service"
            _menu_item  4  "Restart Service"
            _menu_item  5  "Stop / Start Service"
            _menu_item  6  "View Logs"
            echo ""
            _menu_hdr "System"
            _menu_item  7  "Update sing-box"
            _menu_item  8  "BBR Enable / Disable"
            _menu_item  9  "VPS Toolbox"
            _menu_item 10  "Reinstall"
            _menu_quit 11  "Uninstall"
            _menu_sep
            echo ""
            _menu_quit  0  "Exit"
        fi

        echo ""
        read -rp "$(echo -e "${YELLOW}  Select: ${NC}")" OPT

        if ! is_installed; then
            case "$OPT" in
                1) do_install;  pause ;;
                8) do_bbr;      pause ;;
                9) do_vps_tools ;;
                0) exit 0 ;;
                *) echo -e "${RED}Not available until sing-box is installed. Choose 1 to install.${NC}"; sleep 1.5 ;;
            esac
            continue
        fi

        case "$OPT" in
            1) show_info;          pause ;;
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
