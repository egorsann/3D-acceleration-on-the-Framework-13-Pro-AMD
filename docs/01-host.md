# 1. Host (Fedora 44)

```bash
sudo bash scripts/host-setup.sh --check     # report only
sudo bash scripts/host-setup.sh             # apply
```

## What it does

1. **Packages** (installed if missing): `qemu-kvm libvirt-daemon-driver-qemu libvirt-daemon-config-network virt-install virt-viewer edk2-ovmf swtpm swtpm-tools virglrenderer mesa-vulkan-drivers vulkan-tools checkpolicy policycoreutils`.
   It also checks that `/usr/lib64/qemu/hw-display-virtio-gpu-gl.so` exists (the module that talks to virglrenderer).
2. **`/etc/libvirt/qemu.conf`: `seccomp_sandbox = 0`** (backup `qemu.conf.bak-pre-3d`). Without it QEMU's seccomp filter blocks the render server that Venus starts.
3. **SELinux module `vgpu3d-venus`** from [`selinux/vgpu3d-venus.te`](../selinux/vgpu3d-venus.te): one rule, `allow svirt_t self:process setpgid`.
   Symptom without it: the guest driver fails with Code 37 and the host journal shows `AVC denied { setpgid } ... svirt_t`. SELinux stays **enforcing**.
4. Restarts `virtqemud`, shows the render node and the host Vulkan devices.

## Things to check yourself

* **Render node.** The VM XML uses `/dev/dri/renderD128`. On a Framework 13 AMD there is one GPU. If your AMD GPU is another node, pass `--rendernode` to `create-vm.sh`/`apply-3d.py`.
  On the author's machine the node is world-writable (`crw-rw-rw-`), so no `render` group handling was needed; if yours is `crw-rw----`, add `qemu` to the `render` group and restart `virtqemud`.
* **Host Vulkan** must show the AMD device (`vulkaninfo --summary`: `AMD Radeon 890M Graphics (RADV STRIX1)`, driver `radv`). The author also checked `VK_KHR_external_memory_fd`,
  dma-buf, DRM format modifiers and timeline semaphores are present (all are in current Mesa).
* **Filesystem.** With the VM disk on **btrfs**, `cache='none'` (O_DIRECT) gave "csum failed" errors on the live qcow2 in the host log. `apply-3d.py` sets `cache='writeback'`.
  If you keep the image on ext4/xfs this is less of a concern, but the setting is harmless.

## Security notes (read before you do this)

* `seccomp_sandbox = 0` weakens the QEMU confinement for **all** libvirt VMs on the host. SELinux still confines QEMU (`svirt_t`) with the one extra permission.
* The guest driver is **test-signed**: Windows must run in test-signing mode and trust a certificate named `CN=vgpu test signing`. That is acceptable for a lab VM that is not your daily
  security boundary; do not do it in a VM that holds secrets you cannot lose.
* Venus exposes the host GPU's Vulkan driver to the guest. A guest compromise therefore reaches a larger attack surface than with plain virtio-gpu 2D.
