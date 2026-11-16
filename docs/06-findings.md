# 6. Findings, measurements and failures

Everything below is from one machine in one afternoon-to-night session (2026-11-16); numbers are small samples, labelled as such.

## Where 3D works

| Context | Result |
|---|---|
| Console (SPICE) session | works: `dwm`, `LogonUI`, `explorer` load `vulkan_virtio`, `vgpu_d3d11`, `dxvk`; `dxdiag` feature level 12_1; `vgpuvram` reports the host memory (47 435 MB on the 48 GB laptop: shared RAM) |
| Remote Desktop session (new session or takeover of the console session) | **no 3D**: `vkCreateInstance` returns `-4` (VK_ERROR_DEVICE_LOST), the adapter shows unknown feature levels |
| wgpu app, default (Vulkan) | crashes: `Application Error`, module `vulkan_virtio.dll`, exception `0x40000015`, fault offset `0x308ded` ([draft report](bug-reports/vgpu3d-vulkan-crash-amd.md)) |
| wgpu app, `--backend dx12` | exits with the same crash (D3D12 runs on the same Vulkan layer) |
| wgpu app, OpenGL | works well: zink on Venus on RADV |

## Measurements

* **Interactive frame rate.** egui app (AMS Studio, wgpu OpenGL), dragging markers, `AMS_STUDIO_FRAME_STATS=1` (frames per second while drawing; its own per-frame cost ~0.9 ms):
  mean 19–24, max 31–32 before the fence patch; same with `vblank_mode=0`; same at half window size. The frame rate after the patch was not logged (the author tested by hand: native feel).
  Note: egui only draws on input, so an idle window prints no stats; drag continuously while measuring.
* **Host while dragging (before the patch).** `gpu_busy_percent` 13–16 % (idle ~2 %); GTT memory flat within ±90 MB (no leak); QEMU threads all below 30 %, no saturated thread (`tools/host-sampler.py` and `top -H`).
* **Display.** Windows reports 2880×1820 @ **75 Hz**, min = max = 75 (WMI `Win32_VideoController`). TestUFO: 73 Hz, 1200 px/s, 16 px/frame, no dropped frames, host panel 120 Hz.
* **FurMark 2** donut, 1080p: ~20 fps, host GPU 80–95 % busy (mean 88 % over 15 s): GPU-bound.
* **YouTube 4K** scrubbing: reported smooth, "like Linux" (subjective). Video decode is on the CPU.
* **Task Manager** shows ~100 % 3D utilisation right after any action while the host GPU idles: an accounting artefact (the driver treats its engine as busy while a command waits, polled on ~10 ms).

## Bugs found

### QEMU 10.2.2 aborts after a guest reboot (3 times) — see [bug-reports/qemu-reset-blob-abort.md](bug-reports/qemu-reset-blob-abort.md)
`virtio_gpu_virgl_map_resource_blob` names each hostmem object `blob[<resource id>]`; `virtio_gpu_virgl_reset()` only calls `virgl_renderer_reset()` and never unparents them; after a guest reboot
resource ids start again at 1, `object_initialize_child` hits the leftover `blob[1]` → `error_abort`. Triggers seen: `virsh reset` (08:33), `pnputil /enable-device` of the 3D adapter (09:05), Windows `shutdown /r` (10:32).
Other restarts survived, so it depends on whether the guest unmapped everything first.

### QEMU 10.2.2 fence poll every 10 ms — see [bug-reports/qemu-fence-poll-10ms.md](bug-reports/qemu-fence-poll-10ms.md)
Venus fences are noticed by a 10 ms timer; interactive apps are capped near 30 fps. Fixed locally by the 1 ms module patch ([docs/04](04-speedups.md)).

### vgpu3d: Vulkan crash and RDP — see [bug-reports/vgpu3d-vulkan-crash-amd.md](bug-reports/vgpu3d-vulkan-crash-amd.md)

### The SPICE console froze on an old frame
Overnight the console showed a frame from 01:45 while Windows was alive (agent answered, clock 08:28). Mouse and keyboard did nothing and no cursor was drawn. A guest restart then hung for minutes.
Not reproduced since; likely related to the same SPICE-GL/virtio-gpu path. A 2-second application freeze after ~25 consecutive drags was seen twice and not reproduced under the sampler.

### The driver's boot guard
`VgpuBootGuard` ≥ 2 makes the driver refuse to load (Code 37). It tripped after quick restarts and after every QEMU crash; see [docs/05](05-usage.md).

### Windows shell flyouts
`ShellHost.exe` crashes (`0xc0000409`, Windows reports a **CFG violation**) when the clock/network flyouts open. With the 3D adapter disabled the behaviour was identical, so the driver is not the cause.
No injected DLLs/IFEO hooks/third-party shell mods were found; the guest is an unpatched build (latest update September 2024). Related but probably different: Microsoft's confirmed
[24H2 shell-component crash after July 2025 updates](https://betanews.com/2025/11/25/microsoft-confirms-windows-11-24h2-bug-that-crashes-the-start-menu-file-explorer-and-more/). Not fixed.

## Setup traps that cost time (in order)

1. **Secure Boot enforced** blocks the test-signed driver: use firmware without enrolled keys; if you switch the NVRAM of an existing install, Windows may not find its boot entry: put a copy of `bootmgfw.efi` at `EFI\Boot\bootx64.efi` on the ESP.
2. **`Import-Certificate` → E_ACCESSDENIED** under the guest agent (SYSTEM): use `certutil -addstore` ([docs/03](03-guest.md)).
3. **Code 37 with a SELinux AVC `setpgid`**: install the one-rule module ([docs/01](01-host.md)). The guard counter was also at 2 at that point; reset it.
4. **btrfs csum errors** on a `cache=none` qcow2.
5. **virt-viewer needs `--attach`** with `listen type='none'/'socket'`, otherwise it may try to start the VM.
6. **`virt-viewer --title`** does not exist in virt-viewer 11.
7. A one-minute healthy run is needed between start cycles (boot guard).
