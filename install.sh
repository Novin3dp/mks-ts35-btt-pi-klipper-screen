#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/novin3dp-ts35"
USER_NAME="${SUDO_USER:-${USER}}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
FLAG_FILE="$USER_HOME/beeper_enabled"
BACKUP_DIR="$USER_HOME/novin3dp-ts35-backups/$(date +%Y%m%d-%H%M%S)"

log() { printf '\n[Novin3dp TS35] %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || fail "Run as a normal user, not root. sudo is used when required."
[[ -d /sys/firmware/devicetree/base ]] || fail "Device Tree is not available."
sudo -v

log "Checking target hardware"
if ! grep -qiE 'sun50i-h616|CB1|bigtreetech' /proc/device-tree/compatible 2>/dev/null; then
    echo "WARNING: this system does not look like the tested CB1/H616 platform."
    read -r -p "Continue anyway? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 1
fi

log "Installing dependencies"
sudo apt-get update
sudo apt-get install -y device-tree-compiler python3-evdev python3-spidev \
    xserver-xorg xserver-xorg-core xserver-xorg-video-fbdev xinit \
    x11-xserver-utils xinput git curl

log "Preparing project files"
sudo mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/overlay"
sudo cp "$PROJECT_DIR/scripts/virtual_touch.py" "$INSTALL_DIR/scripts/"
sudo cp "$PROJECT_DIR/scripts/beeper_watcher.py" "$INSTALL_DIR/scripts/"
sudo cp "$PROJECT_DIR/overlay/ts35_cb1.dts" "$INSTALL_DIR/overlay/"
sudo chmod 755 "$INSTALL_DIR/scripts/"*.py

log "Backing up existing configuration"
sudo mkdir -p "$BACKUP_DIR"
for f in /boot/armbianEnv.txt /etc/X11/xorg.conf.d/99-ts35-fbdev.conf \
         "$USER_HOME/printer_data/config/printer.cfg" "$USER_HOME/printer_data/config/KlipperScreen.conf"; do
    if [[ -f "$f" ]]; then
        sudo cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak"
    fi
done
printf '%s\n' "$BACKUP_DIR" | sudo tee "$INSTALL_DIR/last_backup" >/dev/null

log "Compiling Device Tree Overlay"
# /opt is root-owned; compile to a temporary user-writable path, then install with sudo.
TMP_DTBO="$(mktemp --suffix=.dtbo)"
trap 'rm -f "$TMP_DTBO"' EXIT
dtc -@ -I dts -O dtb -o "$TMP_DTBO" "$INSTALL_DIR/overlay/ts35_cb1.dts"
sudo mkdir -p /boot/overlay-user
sudo cp "$TMP_DTBO" /boot/overlay-user/ts35_cb1.dtbo
sudo cp "$TMP_DTBO" "$INSTALL_DIR/overlay/ts35_cb1.dtbo"

log "Enabling TS35 overlay"
[[ -f /boot/armbianEnv.txt ]] || fail "/boot/armbianEnv.txt not found. This installer targets Armbian/CB1."
if grep -q '^user_overlays=' /boot/armbianEnv.txt; then
    if ! grep -qE '^user_overlays=.*(^|[[:space:]])ts35_cb1([[:space:]]|$)' /boot/armbianEnv.txt; then
        sudo sed -i 's/^user_overlays=.*/& ts35_cb1/' /boot/armbianEnv.txt
    fi
else
    echo 'user_overlays=ts35_cb1' | sudo tee -a /boot/armbianEnv.txt >/dev/null
fi

log "Installing Xorg framebuffer configuration"
sudo mkdir -p /etc/X11/xorg.conf.d
sudo cp "$PROJECT_DIR/xorg/99-ts35-fbdev.conf" /etc/X11/xorg.conf.d/99-ts35-fbdev.conf

log "Installing KlipperScreen"
if [[ -d "$USER_HOME/KlipperScreen/.git" ]]; then
    git -C "$USER_HOME/KlipperScreen" pull --ff-only
else
    git clone https://github.com/KlipperScreen/KlipperScreen.git "$USER_HOME/KlipperScreen"
fi
sudo chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/KlipperScreen"
pushd "$USER_HOME/KlipperScreen" >/dev/null
BACKEND="X" SERVICE="Y" NETWORK="N" START="1" ./scripts/KlipperScreen-install.sh
popd >/dev/null

log "Installing virtual-touch service"
sed -e "s#__TS35_BEEPER_FLAG__#$FLAG_FILE#g" \
    "$PROJECT_DIR/services/virtual-touch.service" | sudo tee /etc/systemd/system/virtual-touch.service >/dev/null

log "Installing beeper watcher service"
sed -e "s#__TS35_USER__#$USER_NAME#g" -e "s#__TS35_BEEPER_FLAG__#$FLAG_FILE#g" \
    "$PROJECT_DIR/services/beeper-watcher.service" | sudo tee /etc/systemd/system/beeper-watcher.service >/dev/null

sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
printf '1\n' | sudo tee "$FLAG_FILE" >/dev/null
sudo chown "$USER_NAME:$USER_NAME" "$FLAG_FILE"

log "Installing Klipper Touch Beep macro"
PRINTER_CFG="$USER_HOME/printer_data/config/printer.cfg"
if [[ -f "$PRINTER_CFG" ]] && ! grep -q '^\[gcode_macro TOGGLE_BEEPER\]' "$PRINTER_CFG"; then
    printf '\n' | sudo tee -a "$PRINTER_CFG" >/dev/null
    sudo tee -a "$PRINTER_CFG" < "$PROJECT_DIR/klipper/toggle_beeper.cfg" >/dev/null
    sudo chown "$USER_NAME:$USER_NAME" "$PRINTER_CFG"
fi

log "Installing KlipperScreen Touch Beep menu"
KS_CFG="$USER_HOME/printer_data/config/KlipperScreen.conf"
MARKER='#~# --- Do not edit below this line. This section is auto generated --- #~#'
if [[ -f "$KS_CFG" ]] && ! grep -q '^\[menu __main more beeper_toggle\]' "$KS_CFG"; then
    if grep -qF "$MARKER" "$KS_CFG"; then
        TMP_FILE="$(mktemp)"
        awk -v marker="$MARKER" -v insert="$PROJECT_DIR/klipperscreen/touch_beep.conf" \
            'BEGIN{added=0} $0==marker && !added { while ((getline line < insert)>0) print line; close(insert); added=1 } {print}' \
            "$KS_CFG" > "$TMP_FILE"
        sudo cp "$TMP_FILE" "$KS_CFG"
        rm -f "$TMP_FILE"
    else
        printf '\n' | sudo tee -a "$KS_CFG" >/dev/null
        sudo tee -a "$KS_CFG" < "$PROJECT_DIR/klipperscreen/touch_beep.conf" >/dev/null
    fi
    sudo chown "$USER_NAME:$USER_NAME" "$KS_CFG"
fi

log "Enabling services"
sudo systemctl daemon-reload
sudo systemctl enable virtual-touch.service beeper-watcher.service
sudo systemctl restart beeper-watcher.service
if [[ -e /dev/spidev0.2 ]]; then
    sudo systemctl restart virtual-touch.service
fi

cat <<EOF

Installation completed.

Backup:
  $BACKUP_DIR

A reboot is required to activate the Device Tree overlay:
  sudo reboot

After reboot:
  systemctl status KlipperScreen --no-pager
  systemctl status virtual-touch.service --no-pager
  systemctl status beeper-watcher.service --no-pager
EOF
