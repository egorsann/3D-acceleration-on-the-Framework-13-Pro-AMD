#!/bin/bash
# Restore the VM from the output of export-vm.sh (same machine, or a fresh Fedora with host-setup.sh already applied).
#   sudo bash scripts/restore-vm.sh ~/vm-backups/win11-pre-3d
# Environment: WIN11_VM=win11. The VM must be shut off (or not exist). It replaces the disk, the UEFI vars + TPM state and the definition.
set -euo pipefail
S=${1:?folder with <vm>.qcow2, <vm>-nvram-tpm.tar, <vm>.xml, SHA256SUMS}; VM=${WIN11_VM:-win11}; C=qemu:///system
[ "$EUID" -eq 0 ] || { echo "run with sudo"; exit 1; }
( cd "$S" && sha256sum -c SHA256SUMS )
if virsh -c $C dominfo $VM >/dev/null 2>&1; then
  [ "$(virsh -c $C domstate $VM)" = "shut off" ] || { echo "$VM is running: shut it down first"; exit 1; }
fi
echo "== disk";            cp --sparse=always "$S/$VM.qcow2" /var/lib/libvirt/images/$VM.qcow2
chown qemu:qemu /var/lib/libvirt/images/$VM.qcow2; chmod 600 /var/lib/libvirt/images/$VM.qcow2
echo "== UEFI vars + TPM"; tar -C / -xpf "$S/$VM-nvram-tpm.tar"
restorecon -RF /var/lib/libvirt/images /var/lib/libvirt/qemu /var/lib/libvirt/swtpm 2>/dev/null || true
echo "== definition";      virsh -c $C define "$S/$VM.xml"
echo "DONE. The ISO images referenced by the XML (if any) must still exist, or remove those cdrom entries (virsh edit $VM)."
