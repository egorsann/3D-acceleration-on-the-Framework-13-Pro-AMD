#!/usr/bin/env bash
# Rebuild the "1 ms fence poll" copy of QEMU's module directory that the win11 VM loads (QEMU_MODULE_DIR in the VM XML).
#
# Why: QEMU 10.2.2 notices finished host-GPU work (Venus fences) with a timer that fires every 10 ms
# (hw/display/virtio-gpu-virgl.c, virtio_gpu_fence_poll). A frame with a few fence waits is capped near 30 fps and
# feels laggy. The timer re-arm is `lea 0xa(%rdx),%rsi` (48 8d 72 0a) followed by `jmp timer_mod`; this copies
# /usr/lib64/qemu to $DEST and changes that 0x0a to 0x01 (1 ms) in hw-display-virtio-gpu-gl.so. Nothing under /usr is touched.
# Measured 2026-11-16: AMS Studio marker drag in the VM went from ~23 fps / laggy to "feels native".
#
# Safe by construction: it patches only if the byte pattern matches exactly once; otherwise it leaves $DEST absent and
# QEMU falls back to the stock module (QEMU searches QEMU_MODULE_DIR first, then its own directory).
# Re-run after a QEMU update (win11-vm does it before every start): it rebuilds when the stock module changed.
set -eu
SRC=/usr/lib64/qemu
DEST=${FENCE_PATCH_DEST:-/tmp/qemu-modules-1ms}
MOD=hw-display-virtio-gpu-gl.so
STAMP=$DEST/.stock-sha256
now=$(sha256sum "$SRC/$MOD" | cut -d' ' -f1)

if [[ -f $STAMP && $(cat "$STAMP") == "$now" && -f $DEST/$MOD ]]; then
  echo "fence patch up to date ($DEST)"; exit 0
fi

rm -rf "$DEST.new"
cp -a "$SRC" "$DEST.new"
python3 -I - "$DEST.new/$MOD" <<'EOF'
import re, sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
pat = bytes.fromhex('488d720ae9')            # lea 0xa(%rdx),%rsi ; jmp rel32
hits = [m.start() for m in re.finditer(re.escape(pat), bytes(d))]
if len(hits) != 1:
    sys.exit(f"pattern found {len(hits)} times (expected 1): QEMU changed, not patching")
d[hits[0] + 3] = 0x01
open(p, 'wb').write(d)
print("patched offset", hits[0])
EOF
echo "$now" > "$DEST.new/.stock-sha256"
chmod -R a+rX "$DEST.new"
chcon -R -t lib_t "$DEST.new" 2>/dev/null || true     # the VM (svirt_t) may read lib_t, not user_tmp_t
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
echo "fence patch built: $DEST"
