#!/bin/bash
# Back up the VM (definition, UEFI vars + TPM state, disk) into a folder, with checksums. Shuts the VM down cleanly first.
#   sudo bash scripts/export-vm.sh ~/vm-backups/win11-pre-3d
# Environment: WIN11_VM=win11. The disk is written with qemu-img convert (only used blocks). The tar keeps owners/permissions:
# Windows' TPM-bound keys and the Secure Boot state live there. Restore with scripts/restore-vm.sh.
set -euo pipefail
D=${1:?destination folder}; VM=${WIN11_VM:-win11}; C=qemu:///system
mkdir -p "$D"
if [ "$(virsh -c $C domstate $VM)" != "shut off" ]; then
  echo "== shutting down $VM (up to 3 min)"
  virsh -c $C shutdown $VM --mode agent 2>/dev/null || virsh -c $C shutdown $VM
  for i in $(seq 180); do [ "$(virsh -c $C domstate $VM)" = "shut off" ] && break; sleep 1; done
  [ "$(virsh -c $C domstate $VM)" = "shut off" ] || { echo "VM did not shut down - close Windows apps and retry"; exit 1; }
fi
UUID=$(virsh -c $C domuuid $VM)
DISK=$(virsh -c $C domblklist $VM --details | awk '$2=="disk"{print $4; exit}')
echo "== definition";  virsh -c $C dumpxml --inactive --security-info $VM > "$D/$VM.xml"
echo "== UEFI vars + TPM state"
tar -C / -cf "$D/$VM-nvram-tpm.tar" "var/lib/libvirt/qemu/nvram/${VM}_VARS.qcow2" "var/lib/libvirt/swtpm/$UUID"
echo "== disk $DISK -> $D/$VM.qcow2"
qemu-img convert -p -O qcow2 "$DISK" "$D/$VM.qcow2.part" && mv "$D/$VM.qcow2.part" "$D/$VM.qcow2"
qemu-img check "$D/$VM.qcow2"
sync
( cd "$D" && sha256sum "$VM.qcow2" "$VM-nvram-tpm.tar" "$VM.xml" > SHA256SUMS )
ls -lh "$D"
echo "DONE. Restore with: sudo bash scripts/restore-vm.sh $D"
