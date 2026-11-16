# 4. The three speed-ups (and what did not help)

Out of the box the console worked but interactive drawing lagged (an egui app dragging markers: mean ~23 fps, never above 31, about 0.5 s behind your hand).
Three host-side changes fixed it; they are all in [`scripts/apply-3d.py`](../scripts/apply-3d.py) and the launcher.

## 1. `max-refresh-rate=120` on SPICE  (latency)

QEMU's SPICE display sends GL frames to the client at a default **maximum of 30 per second** (`-spice max-refresh-rate=N`, new in QEMU 10.x; see the
[patch series](https://patchew.org/QEMU/20250529051352.1409904-1-vivek.kasireddy@intel.com/20250529051352.1409904-5-vivek.kasireddy@intel.com)). libvirt 12.0 cannot set it. Two facts make the workaround possible:

* QEMU honours the **last** `-spice` option (tested: with two options only the second one's socket was created).
* If the SPICE socket has a **fixed path** (`<listen type='socket' socket='…'/>`), a second `-spice` with identical arguments plus `max-refresh-rate=120` can be appended through `<qemu:commandline>`.

Effect: the frame rate inside the guest did not change (still ~23 mean / 31 max), but the window followed the hand much more closely ("by far the snappiest so far"): finished frames reached the viewer sooner.

## 2. The 1 ms fence poll  (the big one)

QEMU 10.2.2 starts virglrenderer **without** the asynchronous-fence flag and notices finished GPU work with a timer: in `hw/display/virtio-gpu-virgl.c`,

```c
static void virtio_gpu_fence_poll(void *opaque) {
    virgl_renderer_poll(); virtio_gpu_process_cmdq(g);
    if (!QTAILQ_EMPTY(&g->cmdq) || !QTAILQ_EMPTY(&g->fenceq))
        timer_mod(gl->fence_poll, qemu_clock_get_ms(QEMU_CLOCK_VIRTUAL) + 10);   // 10 ms
}
```
A frame that waits for the GPU a few times costs a few × up to 10 ms, which caps interactive apps near 30 fps. The driver author's notes describe the same ~10 ms fence round trip.
Evidence it was the cause: host GPU 13–16 % busy, no saturated QEMU thread, the frame rate did not depend on window size (so not a pixel-copy cost), then the patch removed the ceiling.

[`scripts/qemu-fence-patch.sh`](../scripts/qemu-fence-patch.sh) copies `/usr/lib64/qemu` to `/tmp/qemu-modules-1ms` and changes one byte in `hw-display-virtio-gpu-gl.so` (`lea 0xa(%rdx),%rsi` → `lea 0x1(%rdx),%rsi`, i.e. 10 ms → 1 ms).
It refuses to patch unless the 5-byte pattern `48 8d 72 0a e9` occurs exactly once, rebuilds when the stock module changes (a QEMU update), and the VM gets `QEMU_MODULE_DIR` pointing at the copy.
QEMU searches that directory first and its own afterwards, so a missing copy simply means the stock 10 ms behaviour. The launcher rebuilds the copy before every start, so a reboot of the host (which clears `/tmp`) is harmless.

Verified loaded: a later QEMU crash printed stack frames from `/tmp/qemu-modules-1ms/hw-display-virtio-gpu-gl.so`.
The proper fix is upstream (enable the async fence callback for Venus); see [the bug-report draft](bug-reports/qemu-fence-poll-10ms.md).

## 3. The viewer through XWayland

`GDK_BACKEND=x11 GDK_SCALE=1 virt-viewer …` felt "a tiny bit snappier" than the native Wayland viewer and avoids a GDK warning about the cursor size at scale 2. Small, subjective; the launcher does it.

## What did not help (so you do not repeat it)

| Tried | Result |
|---|---|
| `vblank_mode=0` (Mesa vsync off) | same frame rate (mean 23, max 31) |
| Half-size AMS window | same sustained rate (26–29): not a pixel-copy bottleneck |
| `-global virtio-vga-gl.max_hostmem=4G` | no change |
| `-trace virtio_gpu*` | no output on Fedora's QEMU (no log trace backend) |
| `HKLM\SOFTWARE\vgpu` → `VsyncHz=120` (DWORD) | Windows stays at 75 Hz (min = max = 75); the driver author reports the same |
| Windows `WsiDxgi`/present tweaks | not tried |

## Reading the numbers

* The guest display is fixed at **75 Hz**; TestUFO measures ~73 Hz with no dropped frames on a 120 Hz laptop panel.
* FurMark 2 (1080p donut) gives ~20 fps while the host GPU is 80–95 % busy: that workload is GPU-bound, so it says little about virtualisation overhead.
  A fair efficiency number needs the same preset run natively on Linux; that comparison has **not** been done.
