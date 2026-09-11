#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${SUDO_USER:-${USER}}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
INSTALL_DIR="/opt/novin3dp-ts35"

[[ "$(id -u)" -ne 0 ]] || { echo "Run as a normal user."; exit 1; }
sudo -v

sudo systemctl disable --now virtual-touch.service 2>/dev/null || true
sudo systemctl disable --now beeper-watcher.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/virtual-touch.service /etc/systemd/system/beeper-watcher.service
sudo systemctl daemon-reload

sudo rm -f /etc/X11/xorg.conf.d/99-ts35-fbdev.conf
sudo rm -f /boot/overlay-user/ts35_cb1.dtbo

if [[ -f /boot/armbianEnv.txt ]]; then
    sudo sed -i -E 's/(^user_overlays=.*)([[:space:]]+)ts35_cb1([[:space:]]*|$)/\1\3/' /boot/armbianEnv.txt
    sudo sed -i '/^user_overlays=[[:space:]]*$/d' /boot/armbianEnv.txt
fi

sudo rm -rf "$INSTALL_DIR"
rm -f "$USER_HOME/beeper_enabled"

cat <<EOF
Novin3dp TS35 files and services were removed.

Klipper and KlipperScreen were NOT removed.

If you want to revert printer.cfg or KlipperScreen.conf, use the backup
created during installation under:
  $USER_HOME/novin3dp-ts35-backups/

A reboot is recommended to fully unload the Device Tree overlay.
EOF
