# 3D acceleration on the Framework 13 Pro AMD

Run **Windows 11 IoT Enterprise LTSC** in a libvirt/QEMU virtual machine on **Fedora 44** with real GPU acceleration from the laptop's
**Radeon 890M**, without passing the GPU through (the host keeps the screen). The Windows guest sees a 3D-capable WDDM graphics adapter;
its Vulkan, OpenGL and Direct3D 9/11/12 calls are forwarded to the host's AMD Vulkan driver (RADV) through virtio-gpu **Venus**.

This repository is the complete, reproducible record of one working setup: the host changes, the VM definition, the guest steps, three
measured speed-ups (one of them a one-byte patch of QEMU), every pitfall that cost time, and honest numbers.

> **Status.** Everything here works on the author's machine (Framework Laptop 13 with Ryzen AI 9 HX 370, see "Tested on"). The guide is
> reconstructed from the author's change log and the scripts were tested piece by piece (see "What was verified"), but a clean-room
> run from an empty disk on a second laptop has **not** been done yet. If you try it, please open an issue with what differed.

## What you get

Measured/observed in the VM console window (single user, one machine; see [docs/06-findings.md](docs/06-findings.md) for the method):

| | Result |
|---|---|
| Interactive drawing (egui app, dragging selection markers) | feels native; before the QEMU fence patch it was capped near 30 frames/s with ~0.5 s lag |
| YouTube 4K, scrubbing | smooth, same feel as on Linux |
| TestUFO | 73 Hz measured (the guest display is fixed at 75 Hz), no dropped frames, 16 px/frame |
| FurMark 2 "donut", 1080p | ~20 fps with the host GPU 80–95 % busy: GPU-bound, not VM-bound |
| Host GPU load while dragging in an interactive app | 13–16 % (idle ~2 %) |

What it does **not** give you: GPU passthrough performance guarantees (this is paravirtualised: expect some overhead; it was never compared
frame-for-frame against native), hardware video decode in the guest, or 3D inside Remote Desktop sessions (see limits below).

## How it works

```
Windows app ─ Vulkan/OpenGL(zink)/D3D(DXVK, vkd3d) ─ vgpu3d WDDM driver ─ virtio-gpu (Venus) ─ QEMU ─ virglrenderer render server ─ RADV ─ Radeon 890M
                                                                                          └─ frame → SPICE (dma-buf, GL) → virt-viewer window
```

* **Guest driver**: [fastchain/vgpu3d](https://github.com/fastchain/vgpu3d) (test-signed WDDM driver + Mesa zink + DXVK/vkd3d-proton). Not part of
  this repo, downloaded from its releases. Tested version: `1.0.26313.18562`.
* **Host**: stock Fedora 44 QEMU 10.2.2 / libvirt 12 / virglrenderer 1.3.0 / Mesa 26.2.6, plus small changes listed below.
* **Display**: SPICE with GL (dma-buf scanout) on a unix socket, viewed with `virt-viewer`.

## What this repo changes (and why)

| Where | Change | Why |
|---|---|---|
| Host libvirt | `seccomp_sandbox = 0` in `/etc/libvirt/qemu.conf` | QEMU's sandbox blocks the Venus render server |
| Host SELinux | module `selinux/vgpu3d-venus.te` (`allow svirt_t self:process setpgid`) | QEMU must be allowed to start the render server in its own process group |
| VM | virtio-gpu with `accel3d`, `blob`, `hostmem=4G`, `venus` | Venus (Vulkan over virtio-gpu) |
| VM | SPICE on a fixed socket with GL, plus a second `-spice` with `max-refresh-rate=120` | libvirt cannot set it; QEMU's default of 30 delayed finished frames |
| VM | `QEMU_MODULE_DIR` → a copy of QEMU's modules with one byte changed (`scripts/qemu-fence-patch.sh`) | QEMU polls GPU fences every 10 ms; 1 ms removed the ~30 fps ceiling |
| VM | disk cache `writeback`, Secure Boot code without enrolled keys | `cache=none` gave btrfs checksum errors on a qcow2; the test-signed driver needs Secure Boot not enforced |
| Guest | driver install with test signing, Fast Startup off, `WGPU_BACKEND=opengl` | see [docs/03-guest.md](docs/03-guest.md) |

Nothing under `/usr` is modified; every change has an undo ([docs/07-rollback.md](docs/07-rollback.md)).

## Quick start

**All automatable steps in one command** (Fedora 44, as your normal user; it asks for sudo where needed):

```bash
bash install.sh --check                                     # only report what is missing
bash install.sh --windows-iso ~/win11-ltsc.iso --virtio-iso ~/virtio-win.iso   # host + launcher + create the VM
```
Installing Windows itself, the guest drivers and the vgpu3d driver stay manual (steps 2-3 below); the script prints what is left. The steps one by one:

1. **Host**: `sudo bash scripts/host-setup.sh` ([docs/01-host.md](docs/01-host.md)).
2. **VM**: get a Windows 11 IoT Enterprise LTSC (2024, build 26100) ISO and `virtio-win.iso`, then
   `sudo bash scripts/create-vm.sh --windows-iso … --virtio-iso …`, start it and install Windows ([docs/02-vm.md](docs/02-vm.md)).
3. **Guest**: install the guest agent and virtio drivers, then the vgpu3d driver ([docs/03-guest.md](docs/03-guest.md)).
4. **Launcher**: `bash scripts/install-launcher.sh` (commands, menu entry with icon, popup service), then open **Windows VM** from your launcher or run `win11-vm`
   ([docs/05-usage.md](docs/05-usage.md)). Read the three rules there first.

## Rules you must know (they cost the author several crashes)

1. **Open the VM with the SPICE console** (`scripts/win11-vm`). Remote Desktop sessions get no 3D.
2. **Never use "Restart" in Windows, and never disable/enable/restart the 3D driver while the VM runs.** A guest reboot can abort QEMU 10.2.2
   (a bug in its virtio-gpu reset, [analysis](docs/bug-reports/qemu-reset-blob-abort.md)). Use **Shut down**, then start the VM again.
3. **Wait about a minute after boot before shutting down.** The driver counts starts and refuses to load at 2 ("Code 37"); the counter clears after a
   minute of healthy running ([docs/05-usage.md](docs/05-usage.md)).

## Known limits

* No 3D in Remote Desktop sessions (Vulkan instance creation fails there). The console window is the only 3D path.
* wgpu/Vulkan programs crash inside `vulkan_virtio.dll` on driver 1.0.26313.18562 here; OpenGL (`WGPU_BACKEND=opengl`) works. Draft report: [docs/bug-reports/vgpu3d-vulkan-crash-amd.md](docs/bug-reports/vgpu3d-vulkan-crash-amd.md).
* The Windows clock/network flyouts (ShellHost) crash with a CFG violation; they do so with the 3D adapter disabled too, so the driver is not the cause (not fixed).
* The guest display is fixed at 75 Hz (the driver offers one mode; `VsyncHz=120` had no effect).
* Task Manager shows ~100 % "3D" right after any action although the host GPU is nearly idle: an accounting artefact of the driver.
* One tested machine, one GPU (Radeon 890M / RADV STRIX1). Other AMD iGPUs/dGPUs are plausible but untested; NVIDIA is the driver author's main target.

## Tested on

* Framework Laptop 13 (AMD Ryzen AI 300 series; Ryzen AI 9 HX 370, Radeon 890M), Fedora 44, kernel 7.3.3, btrfs on LUKS
* qemu-kvm 10.2.2-1.fc44, libvirt 12.0.0-6.fc44, virglrenderer 1.3.0-1.fc44, mesa-vulkan-drivers 26.2.6-1.fc44, edk2-ovmf 20260812-10.fc44, swtpm 0.10.2-1.fc44, virt-viewer 11.0-18.fc44
* Guest: Windows 11 IoT Enterprise LTSC 2024 (build 26100.1742, the registry still calls it "Windows 10"), vgpu3d 1.0.26313.18562

## What was verified

* Verified on the author's machine, end to end: the final setup and every measurement in docs/06.
* Verified by test: `scripts/apply-3d.py` turns the author's original (pre-3D) VM definition into the working one (identical apart from IDs), is idempotent, and libvirt accepts
  the output; `scripts/create-vm.sh --dry-run` generates XML that libvirt accepts; `scripts/qemu-fence-patch.sh` reproduces the patched module byte for byte; the health check runs in the guest.
* **Not** verified: a fresh Windows install into the generated VM, the stock interactive `vgpu3d-setup-*.exe` installer (the author used the zip + `install.ps1`), and any other hardware.

## Repository layout

```
docs/                     step-by-step guide, measurements, rollback, bug-report drafts
install.sh                everything automatable in one command (host-setup + install-launcher + optional create-vm, --check mode)
scripts/host-setup.sh     host changes (idempotent, --check mode)
scripts/create-vm.sh      builds the VM (virt-install + apply-3d.py)
scripts/apply-3d.py       turns any Windows VM XML into the 3D configuration (idempotent)
scripts/qemu-fence-patch.sh  builds the 1 ms fence-poll copy of QEMU's modules
scripts/win11-vm          launcher: start, wait, open the console, clean shutdown (waits for the 3D driver's boot counter, repairs a locked driver)
scripts/win11-vm-guard    read/clear the driver's boot counter through the guest agent
scripts/win11-vm-notify   popups for start / up / off / crash (user service, win11-vm-notify.service)
scripts/install-launcher.sh  installs the launcher, icon, menu entry and the popup service for your user
scripts/guest-ps.py       run PowerShell in the guest through the QEMU guest agent
scripts/guest/            PowerShell for inside Windows (prepare, certificate fallback, env, boot guard, health check)
selinux/                  the SELinux module source
tools/host-sampler.py     host GPU/QEMU sampler used for the measurements
```

## Credits and licences

* The Windows guest driver is [fastchain/vgpu3d](https://github.com/fastchain/vgpu3d) (its repository does not state a licence at the time of writing): **nothing from it is redistributed here**.
  Venus is Mesa/virglrenderer/QEMU work; zink, DXVK and vkd3d-proton are bundled by that driver.
* Windows is not included. You need your own licence or evaluation copy.
* Scripts and documents in this repository: MIT, see [LICENSE](LICENSE). No warranty. These steps put a test-signed kernel driver into a VM and disable QEMU's seccomp sandbox on
  the host; back up the VM first and read the security notes in [docs/01-host.md](docs/01-host.md).
