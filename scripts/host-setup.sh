#!/usr/bin/env bash
# Host preparation for 3D (Venus) in a libvirt/QEMU Windows guest on Fedora 44 (Framework 13 AMD, Radeon 890M).
#   sudo bash scripts/host-setup.sh            # apply
#   sudo bash scripts/host-setup.sh --check    # only report, change nothing
# What it does (each step is idempotent and has an undo, see docs/07-rollback.md):
#   1. checks the packages and the Venus-capable QEMU module are present (installs the packages unless --check)
#   2. /etc/libvirt/qemu.conf: seccomp_sandbox = 0   (QEMU's sandbox blocks the process the Venus render server needs)
#   3. installs the tiny SELinux module selinux/vgpu3d-venus.te  (allow svirt_t self:process setpgid)
#   4. restarts virtqemud and checks the render node and host Vulkan
set -euo pipefail
CHECK=0; [[ ${1:-} == --check ]] && CHECK=1
[[ $CHECK -eq 1 || $EUID -eq 0 ]] || { echo "run with sudo (or use --check)"; exit 1; }
R=$(cd "$(dirname "$0")/.." && pwd)
ok()   { printf '  [ok]   %s\n' "$*"; }
todo() { printf '  [todo] %s\n' "$*"; }

echo "== 1. packages"
PKGS=(qemu-kvm libvirt-daemon-driver-qemu libvirt-daemon-config-network virt-install virt-viewer edk2-ovmf swtpm swtpm-tools
      virglrenderer mesa-vulkan-drivers vulkan-tools checkpolicy policycoreutils python3)
missing=(); for p in "${PKGS[@]}"; do rpm -q "$p" &>/dev/null || missing+=("$p"); done
if ((${#missing[@]})); then
  todo "missing packages: ${missing[*]}"
  [[ $CHECK -eq 1 ]] || dnf install -y "${missing[@]}"
else ok "all packages present"; fi
if [[ -e /usr/lib64/qemu/hw-display-virtio-gpu-gl.so ]]; then ok "QEMU has the virtio-gpu GL module"
else todo "/usr/lib64/qemu/hw-display-virtio-gpu-gl.so missing: install the qemu package that ships it (dnf provides '*/hw-display-virtio-gpu-gl.so')"; fi
echo "   qemu: $(rpm -q qemu-kvm)   libvirt: $(rpm -q libvirt-daemon-driver-qemu)   virglrenderer: $(rpm -q virglrenderer)   mesa: $(rpm -q mesa-vulkan-drivers)"

echo "== 2. libvirt: seccomp_sandbox = 0"
CONF=/etc/libvirt/qemu.conf
if [[ ! -r $CONF ]]; then echo "  [skip] cannot read $CONF without root: run 'sudo bash scripts/host-setup.sh --check'"
elif grep -Eq '^\s*seccomp_sandbox\s*=\s*0' "$CONF"; then ok "already 0"
else
  todo "seccomp_sandbox is not 0"
  if [[ $CHECK -eq 0 ]]; then
    [[ -e $CONF.bak-pre-3d ]] || cp -a "$CONF" "$CONF.bak-pre-3d"
    if grep -Eq '^\s*#?\s*seccomp_sandbox' "$CONF"; then sed -i -E 's|^\s*#?\s*seccomp_sandbox\s*=.*|seccomp_sandbox = 0|' "$CONF"
    else echo 'seccomp_sandbox = 0' >> "$CONF"; fi
    ok "set (backup: $CONF.bak-pre-3d)"; RESTART=1
  fi
fi

echo "== 3. SELinux module vgpu3d-venus"
if [[ $EUID -ne 0 ]]; then echo "  [skip] needs root to list modules: run 'sudo bash scripts/host-setup.sh --check'"
elif semodule -l | grep -qx 'vgpu3d-venus'; then ok "already installed"
else
  todo "module not installed"
  if [[ $CHECK -eq 0 ]]; then
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    checkmodule -M -m -o "$T/vgpu3d-venus.mod" "$R/selinux/vgpu3d-venus.te"
    semodule_package -o "$T/vgpu3d-venus.pp" -m "$T/vgpu3d-venus.mod"
    semodule -i "$T/vgpu3d-venus.pp"; ok "installed"
  fi
fi
getenforce | sed 's/^/   SELinux: /'

echo "== 4. services, render node, host Vulkan"
if [[ $CHECK -eq 0 && ${RESTART:-0} -eq 1 ]]; then systemctl restart virtqemud && ok "virtqemud restarted"; fi
ls -l /dev/dri/renderD* 2>/dev/null | sed 's/^/   /' || todo "no /dev/dri/renderD* node"
echo "   (the VM XML uses renderD128; if your AMD GPU is another node, run apply-3d.py with --rendernode)"
if command -v vulkaninfo >/dev/null; then
  vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverName|apiVersion' | head -6 | sed 's/^/   /'
else todo "vulkaninfo missing (package vulkan-tools)"; fi
echo "Done. Next: scripts/create-vm.sh (docs/02-vm.md)."
