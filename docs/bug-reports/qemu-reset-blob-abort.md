# QEMU: virtio-gpu (Venus) aborts after a guest reboot: duplicate `blob[<id>]` child object

*Draft, not yet filed upstream. Reproduced three times on QEMU 10.2.2.*

## Environment
Fedora 44, qemu-kvm 10.2.2-1.fc44, virglrenderer 1.3.0-1.fc44, libvirt 12.0.0, Mesa 26.2.6 (RADV, AMD Radeon 890M).
Guest: Windows 11 IoT Enterprise LTSC 24H2 with the vgpu3d WDDM driver (Venus: `-global virtio-vga-gl.blob=true,hostmem=4G,venus=true`, SPICE with GL).

## Symptom
`qemu-system-x86_64` terminates with SIGABRT while the guest (re)initialises its 3D driver after a reset:

```
#3  error_handle.part.0.cold
#4  error_setv
#5  error_setg_internal
#6  object_property_try_add
#7  object_property_try_add_child
#8  object_initialize_child_with_propsv
#9  object_initialize_child_with_props
#10 object_initialize_child_internal
#11 virtio_gpu_virgl_map_resource_blob      (hw-display-virtio-gpu-gl.so)
#12 virtio_gpu_virgl_process_cmd
#13 virtio_gpu_process_cmdq
#14 virtio_gpu_gl_handle_ctrl
```
Libvirt reports the domain as `shut off (crashed)`.

## Triggers observed
1. `virsh reset <domain>` (hard reset),
2. disabling and re-enabling the guest's 3D display adapter (`pnputil /enable-device`), and
3. a normal Windows restart (`shutdown /r`).
Other restarts of the same guest did not crash, so it depends on what the guest had mapped when the reset happened.

## Analysis (QEMU v10.2.2, `hw/display/virtio-gpu-virgl.c`)
`virtio_gpu_virgl_map_resource_blob()` creates the host-memory region object with a name derived from the resource id:

```c
name = g_strdup_printf("blob[%" PRIu32 "]", res->base.resource_id);
object_initialize_child(OBJECT(g), name, vmr, TYPE_VIRTIO_GPU_VIRGL_HOSTMEM_REGION);
```
`object_initialize_child()` aborts (`error_abort`) if a child with that name already exists. The normal unmap path (`virtio_gpu_virgl_unmap_resource_blob()`, from `resource_unref`)
removes the child asynchronously with `object_unparent()`. The reset path does not:

```c
void virtio_gpu_virgl_reset(VirtIOGPU *g)
{
    virgl_renderer_reset();
}
```
After a reset the guest numbers its resources from 1 again; if a mapped blob with the same id was still present when the reset happened, the next `MAP_BLOB` collides with the old `blob[<id>]` object.

## Suggested fix
On reset, unmap (and unparent) every blob region that is still mapped before reusing resource ids, e.g. walk `g->reslist` calling the unmap helper (handling the asynchronous finalisation), or make the child name unique
(for example by using a monotonically increasing counter instead of the resource id) so a leftover region can never collide.

## Impact
The whole VM dies (all guest state lost) when a Venus guest restarts or its display driver is reset. Workaround: always shut the guest down and start a new QEMU process.
