import os, time, subprocess, sys
D="/sys/class/drm/card1/device/"
def rd(n):
    try: return int(open(D+n).read())
    except: return -1
def procs():
    q=None; rs=[]; 
    for p in os.listdir("/proc"):
        if not p.isdigit(): continue
        try:
            cm=open(f"/proc/{p}/comm").read().strip()
            if cm not in ("qemu-system-x86","virgl_render_se"): continue
            st=open(f"/proc/{p}/stat").read().rsplit(")",1)[1].split()
            cpu=int(st[11])+int(st[12]); rss=int(st[21])*4096//1048576
            (rs if cm.startswith("virgl") else (lambda l:l)([])).append((cpu,rss)) if cm.startswith("virgl") else None
            if cm=="qemu-system-x86": q=(cpu,rss)
        except Exception: pass
    return q, rs
t0=time.time(); prev=None
out=open("samples.csv","w"); out.write("t,gtt_mb,vram_mb,gpu_busy,qemu_cpu_pct,qemu_rss_mb,rs_n,rs_cpu_pct,rs_rss_mb\n")
tck=os.sysconf("SC_CLK_TCK")
while time.time()-t0 < float(sys.argv[1]):
    q,rs=procs(); now=time.time()
    qc=q[0] if q else 0; rc=sum(c for c,_ in rs)
    if prev:
        dt=now-prev[0]
        out.write("%.1f,%d,%d,%d,%.0f,%d,%d,%.0f,%d\n"%(now-t0,rd("mem_info_gtt_used")//1048576,rd("mem_info_vram_used")//1048576,rd("gpu_busy_percent"),100*(qc-prev[1])/tck/dt,q[1] if q else 0,len(rs),100*(rc-prev[2])/tck/dt,sum(r for _,r in rs)))
        out.flush()
    prev=(now,qc,rc); time.sleep(0.5)
