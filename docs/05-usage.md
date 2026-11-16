# 5. Daily use

```bash
scripts/win11-vm              # start if needed, wait for Windows, open the SPICE console
scripts/win11-vm --shutdown   # clean shutdown
```
Put it on your PATH or into a `.desktop` entry; the launcher needs `virsh`, `virt-viewer`, optionally `kdialog`/`notify-send`. Set `WIN11_VM=name` if your domain is not called `win11`.
Log in at the Windows login screen of the console window (the password is typed by you; nothing here stores it).

## The three rules

1. **Console only.** Remote Desktop sessions get no 3D (and taking over the console session by RDP cuts it off). Use `scripts/win11-vm`.
2. **Shut down, never "Restart"**, and do not disable/enable/restart the 3D adapter (Device Manager, `pnputil /restart-device`) while the VM runs.
   A guest reboot or driver re-initialisation in a running VM can make QEMU 10.2.2 abort with a SIGABRT ([analysis](bug-reports/qemu-reset-blob-abort.md)): Windows disappears with the console window.
   It happened 3 times in testing and not on every reboot. A full shutdown followed by a fresh `virsh start` is always safe because it is a new QEMU process.
3. **Give it a minute.** The driver increments `VgpuBootGuard` (`HKLM\SYSTEM\CurrentControlSet\Services\VioGpu3D`) at every start and clears it after about a minute of healthy running.
   At 2 it refuses to start (Device Manager Code 37, Windows falls back to a basic display, which still works but is slow). Quick shutdown/start cycles or a QEMU crash cause it.

## Recovery: "Code 37" / no 3D after a crash or quick restarts

```bash
python3 scripts/guest-ps.py -f scripts/guest/03-reset-boot-guard.ps1        # guard back to 0 (works even with a basic display)
python3 scripts/guest-ps.py 'shutdown /s /t 3'                              # full shutdown, NOT /r
scripts/win11-vm                                                            # start again and wait a minute
python3 scripts/guest-ps.py -f scripts/guest/check.ps1                      # Driver status should be OK, Boot guard 0
```

## If the console freezes on an old frame

Once the console showed a frame from seven hours earlier while Windows was alive (the guest agent still answered, the clock inside was current). A guest restart then hung and a `virsh reset`
aborted QEMU. If it happens: check `virsh qemu-agent-command win11 '{"execute":"guest-ping"}'`; if Windows answers, try closing and reopening the viewer first (`scripts/win11-vm`), and prefer
`virsh shutdown` (waits up to a few minutes) over `reset`. The cause of that freeze was not found.

## Running programs

* AMS Studio-style Rust/wgpu apps: just start them; `WGPU_BACKEND=opengl` was set machine-wide in [docs/03](03-guest.md). Check the adapter line in their About box (`zink Vulkan 1.4 (Virtio-GPU Venus (… RADV …))`).
* Games and benchmarks: Direct3D 11/12 go through DXVK/vkd3d-proton on Venus; FurMark 2 ran GPU-bound at 1080p.
* Windows' own clock/network flyouts crash (ShellHost, a CFG violation, independent of the 3D driver); open Settings instead.
