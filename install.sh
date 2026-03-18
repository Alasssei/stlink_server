#!/bin/bash

set -e

REPO_URL="git@github.com:Alasssei/stlink_server.git"
APP_DIR="/home/aboba/stlink_server"
USER="aboba"

echo "================================================"
echo "   STLink Server - Auto Install Script"
echo "================================================"

# ── 1. ОНОВЛЕННЯ СИСТЕМИ ──
echo "[1/7] Оновлення системи..."
sudo apt-get update -q
sudo apt-get upgrade -y -q

# ── 2. ВСТАНОВЛЕННЯ ЗАЛЕЖНОСТЕЙ ──
echo "[2/7] Встановлення залежностей..."
sudo apt-get install -y -q \
    python3 \
    python3-pip \
    python3-flask \
    openocd \
    git \
    usbutils

# ── 3. КЛОНУВАННЯ РЕПОЗИТОРІЮ ──
echo "[3/7] Клонування репозиторію..."
if [ -d "$APP_DIR" ]; then
    echo "  Папка вже існує — оновлюємо..."
    cd "$APP_DIR"
    git pull origin main
else
    git clone "$REPO_URL" "$APP_DIR"
fi

# ── 4. МЕРЕЖА — ТОЧКА ДОСТУПУ ──
echo "[4/7] Налаштування WiFi точки доступу (STLink-Server)..."
sudo nmcli connection delete MyHotspot 2>/dev/null || true
sudo nmcli connection add \
    type wifi \
    ifname wlan0 \
    con-name MyHotspot \
    autoconnect yes \
    ssid "STLink-Server" \
    -- \
    wifi.mode ap \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "12345678" \
    ipv4.method shared \
    connection.autoconnect-priority 50
sudo nmcli connection up MyHotspot

# ── 5. МЕРЕЖА — СТАТИЧНИЙ ETHERNET ──
echo "[5/7] Налаштування Ethernet (192.168.1.10)..."
sudo nmcli connection delete eth0-static 2>/dev/null || true
sudo nmcli connection add \
    type ethernet \
    ifname eth0 \
    con-name eth0-static \
    autoconnect yes \
    -- \
    ipv4.method manual \
    ipv4.addresses "192.168.1.10/24" \
    connection.autoconnect-priority 100
sudo nmcli connection up eth0-static 2>/dev/null || true

# ── 6. SUDOERS ──
echo "[6/7] Налаштування sudoers..."
echo "aboba ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/aboba > /dev/null
sudo chmod 440 /etc/sudoers.d/aboba

# ── 7. SYSTEMD СЕРВІС ──
echo "[7/7] Створення systemd сервісу..."
sudo tee /etc/systemd/system/stlink.service > /dev/null <<EOF
[Unit]
Description=ST-Link Web Server
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3 $APP_DIR/main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable stlink
sudo systemctl restart stlink

echo ""
echo "================================================"
echo "   Готово! Сервер запущено."
echo "   WiFi: STLink-Server / 12345678"
echo "   Відкрий: http://10.42.0.1:5000"
echo "   Або:     http://192.168.1.10:5000"
echo "================================================"
