#!/bin/bash

set -e

REPO_URL="https://github.com/Alasssei/stlink_server.git"
APP_DIR="/home/aboba/stlink_server"
USER="aboba"

echo "================================================"
echo "   STLink Server - Auto Install Script"
echo "================================================"

# ── 1. ОНОВЛЕННЯ СИСТЕМИ ──
echo "[1/8] Оновлення системи..."
sudo apt-get update -q
sudo apt-get upgrade -y -q

# ── 2. ВСТАНОВЛЕННЯ ЗАЛЕЖНОСТЕЙ ──
echo "[2/8] Встановлення залежностей..."
sudo apt-get install -y -q \
    python3 \
    python3-pip \
    python3-flask \
    openocd \
    git \
    usbutils \
    xserver-xorg x11-xserver-utils xinit \
    chromium unclutter fonts-noto-color-emoji xinput

# ── 3. КЛОНУВАННЯ РЕПОЗИТОРІЮ ──
echo "[3/8] Клонування репозиторію..."
if [ -d "$APP_DIR" ]; then
    echo "  Папка вже існує — оновлюємо..."
    cd "$APP_DIR"
    git pull origin main
else
    git clone "$REPO_URL" "$APP_DIR"
fi

# ── 4. МЕРЕЖА — ТОЧКА ДОСТУПУ ──
echo "[4/8] Налаштування WiFi точки доступу (STLink-Server)..."
sudo raspi-config nonint do_wifi_country UA
sudo rfkill unblock wifi
sleep 2
sudo ip link set wlan0 up
sleep 1
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
sudo nmcli connection up MyHotspot ifname wlan0 2>/dev/null || true

# ── 5. МЕРЕЖА — ETHERNET ──
echo "[5/8] Налаштування Ethernet..."
sudo nmcli connection delete eth0-static 2>/dev/null || true
sudo nmcli connection add \
    type ethernet \
    ifname eth0 \
    con-name eth0-static \
    autoconnect yes \
    -- \
    ipv4.method auto \
    ipv4.dns "8.8.8.8" \
    connection.autoconnect-priority 100
sudo nmcli connection up eth0-static 2>/dev/null || true

# ── 6. SUDOERS ──
echo "[6/8] Налаштування sudoers..."
echo "aboba ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/aboba > /dev/null
sudo chmod 440 /etc/sudoers.d/aboba

# ── 7. ДИСПЛЕЙ ──
echo "[7/8] Налаштування дисплея Hosyond 3.5..."

# Xwrapper
echo 'allowed_users=anybody
needs_root_rights=yes' | sudo tee /etc/X11/Xwrapper.config

# Калібровка тачу
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/99-calibration.conf > /dev/null <<EOF2
Section "InputClass"
        Identifier      "calibration"
        MatchDriver     "libinput"
        MatchIsTouchscreen "on"
        Option  "CalibrationMatrix"  "-1 0 1 0 1 0 0 0 1"
EndSection
EOF2

# Xorg fbdev
sudo tee /etc/X11/xorg.conf.d/99-fbdev.conf > /dev/null <<EOF2
Section "Device"
    Identifier "myfb"
    Driver "fbdev"
    Option "fbdev" "/dev/fb1"
EndSection
Section "Screen"
    Identifier "myscreen"
    Device "myfb"
    DefaultDepth 16
    SubSection "Display"
        Depth 16
        Modes "480x320"
    EndSubSection
EndSection
EOF2

# config.txt — дисплей
sudo sed -i 's/dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/' /boot/firmware/config.txt
grep -q 'dtoverlay=piscreen' /boot/firmware/config.txt || echo 'dtparam=spi=on
dtoverlay=piscreen,speed=32000000,rotate=90' | sudo tee -a /boot/firmware/config.txt

# Chromium профіль — вимкнути переклад
mkdir -p /home/$USER/.config/chromium/Default
cat > /home/$USER/.config/chromium/Default/Preferences << 'EOF2'
{
  "translate":{"enabled":false},
  "translate_blocked_languages":["uk","ru"]
}
EOF2

# ── 8. SYSTEMD СЕРВІСИ ──
echo "[8/8] Створення systemd сервісів..."

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

sudo tee /etc/systemd/system/kiosk.service > /dev/null <<EOF
[Unit]
Description=Kiosk Display
After=stlink.service
Requires=stlink.service

[Service]
User=$USER
Environment=FRAMEBUFFER=/dev/fb1
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c "FRAMEBUFFER=/dev/fb1 startx -- -nocursor"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/chromium.service > /dev/null <<EOF
[Unit]
Description=Chromium Kiosk
After=kiosk.service
Requires=kiosk.service

[Service]
User=$USER
Environment=DISPLAY=:0
ExecStartPre=/bin/sleep 8
ExecStartPre=/bin/bash -c 'killall chromium 2>/dev/null; true'
ExecStart=chromium \
  --kiosk \
  --no-sandbox \
  --disable-gpu \
  --window-size=480,320 \
  --window-position=0,0 \
  --disable-session-crashed-bubble \
  --disable-restore-session-state \
  --no-first-run \
  --disable-infobars \
  --disable-features=TranslateUI,Translate \
  --disable-translate \
  --lang=uk-UA \
  http://localhost:5000/touch
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable stlink.service kiosk.service chromium.service
sudo systemctl restart stlink.service

# Автологін
echo "[+] Налаштування автологіну..."
sudo raspi-config nonint do_boot_behaviour B2

# Вимкнення непотрібних сервісів
echo "[+] Вимкнення непотрібних сервісів..."
sudo systemctl disable cloud-init-main.service 2>/dev/null || true
sudo systemctl disable cloud-init-local.service 2>/dev/null || true
sudo systemctl disable cloud-final.service 2>/dev/null || true
sudo systemctl disable cloud-config.service 2>/dev/null || true
sudo systemctl disable ModemManager.service 2>/dev/null || true
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

echo ""
echo "================================================"
echo "   Готово! Перезавантаж: sudo reboot"
echo "   WiFi: STLink-Server / 12345678"
echo "   Відкрий: http://10.42.0.1:5000"
echo "   Або: підключи ethernet до роутера"
echo "================================================"