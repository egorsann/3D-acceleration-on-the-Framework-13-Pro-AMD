#!/usr/bin/env bash
# One command for everything that can be automated on a Fedora 44 host (Framework 13 AMD):
#   bash install.sh                                              host setup + launcher (asks for sudo where needed)
#   bash install.sh --windows-iso ~/win11-ltsc.iso --virtio-iso ~/virtio-win.iso
#                                                                ... and also create the VM, ready for the Windows install
#   bash install.sh --check                                      only report what is missing, change nothing
# Not automatable (printed at the end): installing Windows, the guest drivers and the vgpu3d driver (docs/02, docs/03).
# Run it as your normal user, not with sudo: the launcher is installed into YOUR home; sudo is used only for the host and VM steps.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
[[ $EUID -ne 0 ]] || { echo "run as your normal user (not root): the launcher goes into your home; sudo is called where needed"; exit 1; }
CHECK=0; WIN_ISO=; VIRTIO_ISO=; EXTRA=()
while (($#)); do case $1 in
  --check) CHECK=1; shift;;
  --windows-iso) WIN_ISO=$2; shift 2;;
  --virtio-iso) VIRTIO_ISO=$2; shift 2;;
  --name|--vcpus|--memory-gib|--disk-gib|--rendernode) EXTRA+=("$1" "$2"); shift 2;;
  -h|--help) sed -n 2,9p "$0"; exit 0;;
  *) echo "unknown option: $1 (see --help)"; exit 1;;
esac; done
[[ -z $WIN_ISO && -z $VIRTIO_ISO ]] || [[ -n $WIN_ISO && -n $VIRTIO_ISO ]] || { echo "give both --windows-iso and --virtio-iso (or neither)"; exit 1; }

. /etc/os-release
[[ ${ID:-} == fedora ]] || echo "WARNING: this is ${PRETTY_NAME:-not Fedora}; the guide was tested on Fedora 44 only"
[[ ${VERSION_ID:-} == 44 ]] || echo "WARNING: Fedora ${VERSION_ID:-?}: tested on 44 (QEMU 10.2.2); the QEMU module patch matches that build only"

if ((CHECK)); then
  echo "== host (read only)"; bash scripts/host-setup.sh --check
  echo "== launcher: would install win11-vm, win11-vm-guard, win11-vm-notify, qemu-fence-patch.sh, icon, menu entry, popup service"
  for f in win11-vm win11-vm-guard win11-vm-notify; do
    if [[ -e ~/.local/bin/$f ]]; then echo "  [ok]   ~/.local/bin/$f"; else echo "  [todo] ~/.local/bin/$f"; fi
  done
  exit 0
fi

echo "== 1/3 host setup (sudo)";    sudo bash scripts/host-setup.sh
echo "== 2/3 launcher and popups";  bash scripts/install-launcher.sh
if [[ -n $WIN_ISO ]]; then
  echo "== 3/3 create the VM (sudo)"; sudo bash scripts/create-vm.sh --windows-iso "$WIN_ISO" --virtio-iso "$VIRTIO_ISO" "${EXTRA[@]}"
else
  echo "== 3/3 VM: skipped (no ISOs given)"
fi

cat <<'MSG'

Done with everything that can be automated. What is left, by hand:
  1. Install Windows 11 IoT Enterprise LTSC in the VM (storage driver from the virtio-win CD during setup)   docs/02-vm.md
     (without --windows-iso/--virtio-iso: first run  sudo bash scripts/create-vm.sh --windows-iso ... --virtio-iso ...)
  2. In Windows: guest agent + virtio drivers, then the vgpu3d driver, test signing, WGPU_BACKEND             docs/03-guest.md
  3. Open "Windows VM" from your launcher. Read the three rules first                                         docs/05-usage.md
Check anything at any time:  bash install.sh --check
MSG
