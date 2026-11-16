#!/usr/bin/env bash
# Installs the launcher for the current user: commands in ~/.local/bin, the icon, a menu/rofi entry and the popup service.
# Safe to re-run. Undo: systemctl --user disable --now win11-vm-notify; rm the files listed below.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
put() {  # put <mode> <source> <destination>; a destination that is a symlink is managed elsewhere (dotfiles): leave it alone
  if [[ -L $3 ]]; then echo "  skipped $3 (symlink, managed elsewhere)"; return; fi
  install -D -m"$1" "$2" "$3"
}
for f in win11-vm win11-vm-guard win11-vm-notify qemu-fence-patch.sh; do put 755 "$f" ~/.local/bin/"$f"; done
put 644 win11-vm.svg ~/.local/share/icons/hicolor/scalable/apps/win11-vm.svg
sed "s|%HOME%|$HOME|" win11-vm.desktop >"${TMPDIR:-/tmp}/win11-vm.desktop.$$"
put 644 "${TMPDIR:-/tmp}/win11-vm.desktop.$$" ~/.local/share/applications/win11-vm.desktop; rm -f "${TMPDIR:-/tmp}/win11-vm.desktop.$$"
put 644 win11-vm-notify.service ~/.config/systemd/user/win11-vm-notify.service
systemctl --user daemon-reload
systemctl --user enable --now win11-vm-notify.service
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
echo "Installed: win11-vm, win11-vm-guard, win11-vm-notify, qemu-fence-patch.sh in ~/.local/bin; menu entry 'Windows VM'; user service win11-vm-notify."
