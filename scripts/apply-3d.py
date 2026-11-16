#!/usr/bin/python3 -I
"""apply-3d.py: turn a libvirt domain XML of a Windows VM into the 3D (Venus) configuration of this repo.

  virsh -c qemu:///system dumpxml --inactive win11 | python3 scripts/apply-3d.py > win11-3d.xml
  python3 scripts/apply-3d.py win11.xml -o win11-3d.xml

Every change is idempotent (running it twice gives the same result). What it sets, and why (docs/04-speedups.md):
  video      virtio with accel3d=yes                                 3D virtio-gpu
  qemu args  -global virtio-vga-gl.blob=true / hostmem=4G / venus=true    Venus (Vulkan over virtio-gpu) + 4 GiB guest-visible host memory
  graphics   SPICE on a fixed unix socket with GL (dma-buf) on the render node
  qemu args  a second -spice with max-refresh-rate=120               libvirt cannot set it; QEMU uses the LAST -spice. Default is 30.
  qemu env   QEMU_MODULE_DIR=/tmp/qemu-modules-1ms                   the 1 ms fence-poll module copy (scripts/qemu-fence-patch.sh)
  disk       cache=writeback                                         cache=none (O_DIRECT) produced btrfs checksum errors on a qcow2
  firmware   Secure Boot code but NO enrolled keys                   the test-signed driver needs Secure Boot not enforced
Needs only the Python 3 standard library.
"""
import argparse, sys
import xml.etree.ElementTree as ET

QEMU_NS = "http://libvirt.org/schemas/domain/qemu/1.0"
ET.register_namespace("qemu", QEMU_NS)
ET.register_namespace("libosinfo", "http://libosinfo.org/xmlns/libvirt/domain/1.0")

def q(tag):
    return "{%s}%s" % (QEMU_NS, tag)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("xml", nargs="?", help="domain XML file (default: stdin)")
    ap.add_argument("-o", "--output", help="output file (default: stdout)")
    ap.add_argument("--rendernode", default="/dev/dri/renderD128")
    ap.add_argument("--socket", default="/var/lib/libvirt/qemu/win11-spice.sock", help="fixed SPICE socket path")
    ap.add_argument("--hostmem", default="4G", help="guest-visible host memory window (virtio-vga-gl hostmem)")
    ap.add_argument("--refresh", type=int, default=120, help="SPICE max-refresh-rate (QEMU default 30)")
    ap.add_argument("--module-dir", default="/tmp/qemu-modules-1ms", help="QEMU_MODULE_DIR for the fence patch ('' = do not set)")
    a = ap.parse_args()

    root = ET.fromstring(open(a.xml).read() if a.xml else sys.stdin.read())
    if root.get("type") != "kvm":
        sys.exit("not a KVM domain")
    dev = root.find("devices")

    # --- firmware: Secure Boot code, no enrolled keys (test signing needs Secure Boot not enforced)
    os_ = root.find("os")
    os_.set("firmware", "efi")
    for old in os_.findall("firmware"):
        os_.remove(old)
    fw = ET.Element("firmware")
    ET.SubElement(fw, "feature", enabled="no", name="enrolled-keys")
    ET.SubElement(fw, "feature", enabled="yes", name="secure-boot")
    os_.insert(list(os_).index(os_.find("type")) + 1, fw)
    nv = os_.find("nvram")
    if nv is not None:
        nv.set("template", "/usr/share/edk2/ovmf/OVMF_VARS_4M.qcow2")
        nv.set("templateFormat", "qcow2")

    # --- disk cache
    for d in dev.findall("disk"):
        if d.get("device") == "disk":
            drv = d.find("driver")
            drv.set("cache", "writeback")

    # --- video: virtio + 3D
    vid = dev.find("video")
    if vid is None:
        vid = ET.SubElement(dev, "video")
    for m in vid.findall("model"):
        vid.remove(m)
    m = ET.SubElement(vid, "model", type="virtio", heads="1", primary="yes")
    ET.SubElement(m, "acceleration", accel3d="yes")

    # --- graphics: SPICE on a fixed socket with GL on the render node
    g = dev.find("graphics")
    if g is None:
        g = ET.SubElement(dev, "graphics", type="spice")
    for k in [k for k in g.attrib if k != "type"]:      # autoport/port/listen belong to TCP; we use a socket
        del g.attrib[k]
    g.set("type", "spice")
    for c in list(g):
        g.remove(c)
    ET.SubElement(g, "listen", type="socket", socket=a.socket)
    ET.SubElement(g, "image", compression="off")
    ET.SubElement(g, "gl", enable="yes", rendernode=a.rendernode)

    # --- qemu:commandline
    cl = root.find(q("commandline"))
    if cl is not None:
        root.remove(cl)
    cl = ET.SubElement(root, q("commandline"))
    for opt in ("virtio-vga-gl.blob=true", "virtio-vga-gl.hostmem=" + a.hostmem, "virtio-vga-gl.venus=true"):
        ET.SubElement(cl, q("arg"), value="-global")
        ET.SubElement(cl, q("arg"), value=opt)
    spice = ("unix=on,addr=%s,disable-ticketing=on,image-compression=off,gl=on,rendernode=%s,"
             "seamless-migration=on,max-refresh-rate=%d" % (a.socket, a.rendernode, a.refresh))
    ET.SubElement(cl, q("arg"), value="-spice")
    ET.SubElement(cl, q("arg"), value=spice)
    if a.module_dir:
        ET.SubElement(cl, q("env"), name="QEMU_MODULE_DIR", value=a.module_dir)

    ET.indent(root, space="  ")
    out = ET.tostring(root, encoding="unicode") + "\n"
    if a.output:
        open(a.output, "w").write(out)
    else:
        sys.stdout.write(out)

if __name__ == "__main__":
    main()
