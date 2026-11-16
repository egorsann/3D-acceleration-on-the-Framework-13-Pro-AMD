# The driver counts starts in HKLM\SYSTEM\CurrentControlSet\Services\VioGpu3D\VgpuBootGuard: +1 at driver start, back to 0 after about a
# minute of healthy running. At >= 2 the driver refuses to start (Device Manager: Code 37, Windows falls back to a basic display).
# This happens after a QEMU crash or quick shutdown/start cycles. Reset it, then do a full SHUT DOWN and start the VM again.
# Do NOT "pnputil /restart-device" or reboot the guest to bring the driver back: that can abort QEMU (docs/06-findings.md).
$k = 'HKLM:\SYSTEM\CurrentControlSet\Services\VioGpu3D'
Write-Output ("guard was: " + (Get-ItemProperty $k).VgpuBootGuard)
Set-ItemProperty $k -Name VgpuBootGuard -Value 0
Write-Output "guard reset to 0: now shut Windows down completely and start the VM again"
