#!/usr/bin/env bash
# Installs the launcher for the current user: commands in ~/.local/bin, the icon, a menu/rofi entry and the popup service.
# Safe to re-run. Undo: systemctl --user disable --now win11-vm-notify; rm the files listed below.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
for f in win11-vm win11-vm-guard win11-vm-notify qemu-fence-patch.sh; do install -D -m755 "$f" ~/.local/bin/"$f"; done
install -D -m644 win11-vm.svg ~/.local/share/icons/hicolor/scalable/apps/win11-vm.svg
sed "s|%HOME%|$HOME|" win11-vm.desktop | install -D -m644 /dev/stdin ~/.local/share/applications/win11-vm.desktop
install -D -m644 win11-vm-notify.service ~/.config/systemd/user/win11-vm-notify.service
systemctl --user daemon-reload
systemctl --user enable --now win11-vm-notify.service
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
echo "Installed: win11-vm, win11-vm-guard, win11-vm-notify, qemu-fence-patch.sh in ~/.local/bin; menu entry 'Windows VM'; user service win11-vm-notify."
