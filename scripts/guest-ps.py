#!/usr/bin/env python3
"""guest-ps.py '<powershell>' : run PowerShell inside the Windows VM through the QEMU guest agent and print its output.

  python3 scripts/guest-ps.py 'Get-PnpDevice -FriendlyName "*vgpu*" | ft Status,FriendlyName -auto | out-string'
  python3 scripts/guest-ps.py -f scripts/guest/check.ps1
Environment: WIN11_VM=win11 (domain name). It runs as SYSTEM in session 0, so it can change the registry, install drivers and read logs
but cannot draw windows. To start a program inside the logged-in console session use a scheduled task with an Interactive principal
(see docs/06-findings.md). Known quirk: the first line of output is sometimes lost; print a throwaway line first if you need it.
"""
import base64, json, os, subprocess, sys, time

VM = os.environ.get("WIN11_VM", "win11")
CONN = "qemu:///system"

def agent(cmd):
    r = subprocess.run(["virsh", "-c", CONN, "qemu-agent-command", VM, json.dumps(cmd)], capture_output=True, text=True, timeout=60)
    if r.returncode:
        raise SystemExit("agent error: " + r.stderr.strip()[:300])
    return json.loads(r.stdout)["return"]

def run(ps, timeout=120):
    enc = base64.b64encode(ps.encode("utf-16-le")).decode()
    pid = agent({"execute": "guest-exec", "arguments": {"path": "powershell.exe",
                 "arg": ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", enc],
                 "capture-output": True}})["pid"]
    end = time.time() + timeout
    while time.time() < end:
        st = agent({"execute": "guest-exec-status", "arguments": {"pid": pid}})
        if st.get("exited"):
            out = base64.b64decode(st.get("out-data", "")).decode("utf-8", "replace")
            err = base64.b64decode(st.get("err-data", "")).decode("utf-8", "replace")
            return st.get("exitcode"), out, err
        time.sleep(1)
    raise SystemExit("timeout waiting for the guest")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    ps = open(sys.argv[2]).read() if sys.argv[1] == "-f" else sys.argv[1]
    rc, out, err = run(ps)
    sys.stdout.write(out)
    if err.strip() and "CLIXML" not in err[:20]:
        sys.stderr.write("[stderr] " + err[:1500])
    sys.exit(rc or 0)
