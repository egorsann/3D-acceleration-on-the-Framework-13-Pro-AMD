# vgpu3d: Vulkan applications crash in `vulkan_virtio.dll`; no 3D in Remote Desktop sessions (AMD host)

*Draft for the driver's repository ([fastchain/vgpu3d](https://github.com/fastchain/vgpu3d)), not yet filed. The driver is mainly tested on NVIDIA; this is an AMD data point.*

## Environment
* Host: Fedora 44, Framework Laptop 13 (Ryzen AI 9 HX 370), Radeon 890M, Mesa 26.2.6 RADV STRIX1, Vulkan 1.4, QEMU 10.2.2, virglrenderer 1.3.0, libvirt 12.0.0, kernel 7.3.3
* VM: `-global virtio-vga-gl.blob=true,hostmem=4G,venus=true`, SPICE with GL; Windows 11 IoT Enterprise LTSC 2024 (build 26100.1742), Secure Boot not enforced, test signing on
* Driver: vgpu3d 1.0.26313.18562 (zip + `install.ps1`; certificate imported with certutil because `Import-Certificate` returned E_ACCESSDENIED under the guest agent)

## What works
Console (SPICE) session: DWM, LogonUI and Explorer load `vulkan_virtio.dll`/`vgpu_d3d11.dll`/DXVK; `dxdiag` shows feature level 12_1; `vgpuvram` reports the host memory; OpenGL through Mesa zink is excellent
(egui/wgpu GL backend: adapter `zink Vulkan 1.4 (Virtio-GPU Venus (AMD Radeon 890M Graphics (RADV STRIX1)) (MESA_RADV))`; FurMark 2 at 1080p runs with the host GPU 80–95 % busy).

## Problem 1: a wgpu (Rust) program on the Vulkan backend crashes
* Faulting module: `vulkan_virtio.dll` (timestamp 0x6af19e04), exception `0x40000015` (STATUS_FATAL_APP_EXIT / abort), fault offset `0x308ded`, reproducible at every start (more than ten crashes logged).
* The same program with `WGPU_BACKEND=opengl` runs fine. With `--backend dx12` (wgpu D3D12 → vkd3d-proton → Venus) it exits with the same crash report.
* I have not isolated which Vulkan call aborts; a minimal Vulkan test (vkcube-like) was not available in the package I used.

## Problem 2: Vulkan fails inside Remote Desktop sessions
In any RDP session (a new session, or taking over the console session) `vkCreateInstance` in `vulkan_virtio.dll` returns `-4` (`VK_ERROR_DEVICE_LOST`) and `dxdiag` shows unknown feature levels for the vgpu adapter. The same code in the console session works. No host-side error appears in the QEMU log.

## Related notes
* After a QEMU crash the boot-guard counter (`VgpuBootGuard`) is left at ≥ 1; the next start then sets it to 2 and the driver refuses to load (Code 37) until the value is reset by hand. A clean way to recover (or an automatic reset when the previous session ended without a clean guest shutdown) would help users after host-side crashes.
* Re-initialising the driver in a running VM (disable/enable) can abort QEMU 10.2.2 (host bug, [separate report](qemu-reset-blob-abort.md)); the changelog says apps now survive adapter restarts, which holds on the guest side.
* The driver's `docs/STATUS.md` says forcing the vsync source to 120 Hz (`HKLM\SOFTWARE\vgpu` `VsyncHz`) does not reliably change the mode; on this setup it did not change it either (Windows stays at 75 Hz).

## What I can provide
Event log excerpts, the host journal, the full change log of this setup (<https://github.com/egorsann/3D-acceleration-on-the-Framework-13-Pro-AMD>), and tests on request.
