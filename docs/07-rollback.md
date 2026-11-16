# 7. Rollback: undo every change

Everything is reversible. Take a backup first (`sudo bash scripts/export-vm.sh ~/vm-backups/win11-pre-3d`); then each piece can be undone on its own.

## Whole VM back to a backup
```bash
sudo bash scripts/restore-vm.sh ~/vm-backups/win11-pre-3d      # the VM must be shut off
```
This restores the disk, the UEFI variables + TPM state and the definition from before the 3D work.

## Only the VM definition (keep the disk)
The 3D settings are XML only. Shut the VM down, then either define a saved XML from before (`virsh define win11-before.xml`), or remove them by hand (`virsh edit win11`):
video `accel3d`, the `qemu:commandline` block (including `-spice` and `qemu:env`), the SPICE socket listen. `apply-3d.py` is idempotent, so you can also re-run it with different options.

## Only the QEMU module patch
Remove `<qemu:env name='QEMU_MODULE_DIR' …/>` from the XML (or `rm -rf /tmp/qemu-modules-1ms`: QEMU then silently uses the stock modules; the launcher would rebuild the copy at the next start, so remove the env instead).

## Host
```bash
sudo semodule -r vgpu3d-venus                                     # SELinux rule
sudo cp -a /etc/libvirt/qemu.conf.bak-pre-3d /etc/libvirt/qemu.conf && sudo systemctl restart virtqemud     # seccomp sandbox back on
```

## Guest (inside Windows, elevated PowerShell)
```powershell
# driver: the package contains uninstall3d.ps1
.\uninstall3d.ps1 -RemoveCert
bcdedit /set testsigning off
setx /M WGPU_BACKEND ""
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v WGPU_BACKEND /f
powercfg /hibernate on        # only if you want hibernation back
```
If the display is broken and you cannot log in, use `scripts/guest-ps.py` from the host (the agent still works), or boot Windows into safe mode and remove the *vgpu* package in Device Manager.

## Temporary SELinux permissive mode
If you followed the experiment trail and ran `semanage permissive -a svirt_t` to collect denials, remove it: `sudo semanage permissive -d svirt_t`. The final setup needs only the module above, with SELinux enforcing.
