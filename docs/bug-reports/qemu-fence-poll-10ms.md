# QEMU: Venus fences are only noticed every 10 ms, capping interactive apps near 30 fps

*Draft, not yet filed upstream. Measured on QEMU 10.2.2.*

## Environment
Fedora 44, qemu-kvm 10.2.2-1.fc44, virglrenderer 1.3.0-1.fc44, Mesa 26.2.6 (RADV, Radeon 890M, shared memory), SPICE with GL (dma-buf), Windows 11 guest with the vgpu3d driver and Mesa zink.

## Symptom
An interactive OpenGL app (egui, wgpu GL backend, dragging markers) in the guest draws about 23 frames/s on average and never above 31, whatever the window size. The host GPU is 13–16 % busy, no QEMU thread is saturated:
the guest is waiting, not computing. The driver author's own notes mention a ~10 ms `vkWaitForFences` round trip although the kernel fence round trip is 0.02–0.07 ms.

## Cause
In `virtio_gpu_virgl_init()` (v10.2.2, `hw/display/virtio-gpu-virgl.c`) the flags passed to `virgl_renderer_init()` contain `VIRGL_RENDERER_VENUS | VIRGL_RENDERER_RENDER_SERVER` but not
`VIRGL_RENDERER_ASYNC_FENCE_CB`. Completed fences are therefore only discovered by a timer:

```c
static void virtio_gpu_fence_poll(void *opaque)
{
    virgl_renderer_poll();
    virtio_gpu_process_cmdq(g);
    if (!QTAILQ_EMPTY(&g->cmdq) || !QTAILQ_EMPTY(&g->fenceq))
        timer_mod(gl->fence_poll, qemu_clock_get_ms(QEMU_CLOCK_VIRTUAL) + 10);
}
```
Each wait for the GPU costs up to 10 ms; a frame with a few waits sits near 30 fps.

## Evidence the timer is the limit
Changing the constant `10` to `1` (a one-byte patch of `hw-display-virtio-gpu-gl.so`, loaded through `QEMU_MODULE_DIR`) removed the ceiling: dragging went from laggy to indistinguishable from native by hand;
TestUFO then showed the guest's 75 Hz with no dropped frames; 4K video scrubbing in the guest browser felt like on the host. (See [../04-speedups.md](../04-speedups.md); a quantitative frame-rate log after the patch was not taken.)

## Suggested change
Request `VIRGL_RENDERER_ASYNC_FENCE_CB` when Venus (or any context-init based capset) is enabled and signal completion from the render-server callback instead of polling; failing that, poll at 1 ms (or adaptively) while fences are in flight.

## Related
SPICE's `max-refresh-rate` defaults to 30 and libvirt (12.0) cannot set it; with a second `-spice` option it can be raised, which improved latency further (this repo, docs/04).
