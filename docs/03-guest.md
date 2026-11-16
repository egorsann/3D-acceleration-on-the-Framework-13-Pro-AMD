# 3. Guest (inside Windows)

Run the commands in an **elevated PowerShell** inside Windows. Every script in `scripts/guest/` can also be sent from the host with the guest agent:

```bash
python3 scripts/guest-ps.py -f scripts/guest/check.ps1        # runs as SYSTEM in session 0
```

## 0. Back up first

`sudo bash scripts/export-vm.sh ~/vm-backups/win11-pre-3d` (see [docs/02](02-vm.md)). The driver is test-signed and touches boot configuration.

## 1. Prepare Windows

```powershell
.\scripts\guest\00-prepare.ps1
```
Turns **hibernation and Fast Startup off** (the driver's README warns that a "shutdown" that is really a hibernate leaves stale GPU state; this guide relies on real shutdowns), and reports Secure Boot,
test signing and the build. **Secure Boot must not be enforced** (`Confirm-SecureBootUEFI` → `False`); the VM definition from this repo has no enrolled keys, which gives exactly that.

## 2. Install the driver

Download from <https://github.com/fastchain/vgpu3d/releases> (tested: **v1.0.26313.18562**):

| File | SHA-256 |
|---|---|
| `vgpu3d-m1.zip` | `d60e0e3a24eabc209c870c6072305db78b35a18c949682d9433775bc11098dba` |
| `vgpu3d-setup-1.0.26313.18562.exe` | `23f9b53d9b2c3bc4b5c6862b5b790a2c09f9e7d0f2063cddc71032476532ef94` |

Verify with `Get-FileHash`. Newer releases may exist; read their changelog (the author documents behaviour changes there).

**Path used by the author (verified): zip + `install.ps1`.** Extract the zip and run `install.ps1` in an elevated PowerShell. It works in two steps:

1. First run: it enables test signing (`bcdedit /set testsigning on`) and asks you to reboot. Reboot the VM (this is the one place a guest **restart** is needed;
   do it **before** the 3D driver is installed, when the QEMU abort of [docs/06](06-findings.md) is not expected because the guest still uses the plain virtio display driver, which does not map GPU blobs; the author's own first reboot at this point was uneventful).
2. Second run: it extracts the test certificate, trusts it as `CN=vgpu test signing` in *Root* and *TrustedPublisher*, and installs the driver with `pnputil` (`oem*.inf`, PCI `VEN_1AF4&DEV_1050`).

If step 2 fails at `Import-Certificate` with **E_ACCESSDENIED** (it did when the script was run through the guest agent as SYSTEM), import the extracted certificate with certutil and run the script again:
```powershell
.\scripts\guest\01-certificate-fallback.ps1
```

**Alternative (not verified by the author): the interactive `vgpu3d-setup-*.exe`** from an elevated desktop session; it should do the same steps.

After installing, **shut Windows down completely and start the VM again** (not "Restart").

## 3. Check

```powershell
.\scripts\guest\check.ps1
```
Expected: `Driver status: vgpu VirtIO GPU 3D (WDDM) = OK`, `Boot guard: 0`, a display with your resolution at **75 Hz**, `Secure Boot: not enforced`, `Test signing: True`.
Windows reports the product as "Windows 10 IoT Enterprise LTSC 2024" in the registry; that is a known naming quirk, the build is 26100 (Windows 11 24H2).

Open the **console window** (`scripts/win11-vm`) and log in. In the console session Task Manager → Performance shows the GPU again, and `dxdiag` shows feature level 12_1 with Direct3D, DirectDraw and AGP texture acceleration enabled.

**If the status is "Error" / Code 37**: the driver's boot-loop guard tripped (counter ≥ 2). Fix: `scripts/guest/03-reset-boot-guard.ps1`, then Shut down and start the VM ([docs/05-usage.md](05-usage.md)).

## 4. Make wgpu/Vulkan apps use OpenGL

```powershell
.\scripts\guest\02-wgpu-opengl.ps1       # setx /M WGPU_BACKEND opengl
```
wgpu-based programs (e.g. AMS Studio) crash inside `vulkan_virtio.dll` on this driver version, and run very well through Mesa zink (OpenGL on Venus) when `WGPU_BACKEND=opengl`.
The adapter then shows as `zink Vulkan 1.4 (Virtio-GPU Venus (AMD Radeon 890M Graphics (RADV STRIX1)))`. Programs started from an Explorer that was already running need Explorer restarted or a re-login to see the variable.
Other Vulkan programs are not affected by this variable; try them one by one.

## 5. Optional: Remote Desktop

A hardware-GPU policy for RDP sessions (`HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services` → `bEnumerateHWBeforeSW` = 1) was set during the experiments, but RDP sessions get **no 3D** with
this driver regardless (Vulkan instance creation fails there), so it brings nothing here. Use the SPICE console.

## Run a program inside the logged-in console session from the host

The agent runs as SYSTEM in session 0 where Vulkan/GL programs fail. To start a program in the interactive session, register a scheduled task with an interactive principal:
```powershell
$u = (query user | Select-String console | % { ($_ -replace '^[> ]+','') -split '\s{2,}' | select -First 1 })
$a = New-ScheduledTaskAction -Execute 'C:\path\to\program.exe' -Argument '--option'
$p = New-ScheduledTaskPrincipal -UserId $u -LogonType Interactive
Register-ScheduledTask -TaskName t1 -Action $a -Principal $p -Force | Out-Null; Start-ScheduledTask t1
```
Do **not** start `explorer.exe` that way: it destabilised the shell (ShellHost crashes) during the experiments.
