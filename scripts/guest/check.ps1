# Health report of the 3D setup inside the guest.
Write-Output "x"
$b = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Write-Output ("OS            : " + $b.ProductName + " build " + $b.CurrentBuild + "." + $b.UBR)
Write-Output ("Driver status : " + ((Get-PnpDevice -FriendlyName '*vgpu*' -ErrorAction SilentlyContinue | % { $_.FriendlyName + " = " + $_.Status }) -join '; '))
Write-Output ("Boot guard    : " + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VioGpu3D' -ErrorAction SilentlyContinue).VgpuBootGuard + "  (0 healthy, 1 just started, >=2 driver refused)")
$v = Get-CimInstance Win32_VideoController | Select-Object -First 1
Write-Output ("Display       : " + $v.Name + "  " + $v.CurrentHorizontalResolution + "x" + $v.CurrentVerticalResolution + " @ " + $v.CurrentRefreshRate + " Hz")
Write-Output ("WGPU_BACKEND  : " + [Environment]::GetEnvironmentVariable('WGPU_BACKEND','Machine'))
Write-Output ("Test signing  : " + (((bcdedit /enum '{current}') -match 'testsigning\s+Yes').Count -gt 0))
try { Write-Output ("Secure Boot   : " + (Confirm-SecureBootUEFI)) } catch { Write-Output "Secure Boot   : not enforced (good)" }
Write-Output ("Fast Startup  : " + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled + "  (0 = off, wanted)")
Write-Output ("Console session: " + [bool]((query user 2>&1) -match 'console'))
