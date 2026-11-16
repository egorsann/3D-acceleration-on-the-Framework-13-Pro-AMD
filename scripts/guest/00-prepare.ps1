# Run inside Windows (elevated PowerShell) or via scripts/guest-ps.py -f. Prepares the guest for the 3D driver.
#  - hibernation and Fast Startup OFF: the driver README warns that a "shutdown" that is really a hibernate leaves stale GPU state,
#    and we rely on real shutdowns (docs/05-usage.md).
#  - reports Secure Boot (must NOT be enforced for the test-signed driver) and test signing.
powercfg /hibernate off
New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Force | Out-Null
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord
Write-Output "hibernate off, Fast Startup off"
try { Write-Output ("Secure Boot enforced: " + (Confirm-SecureBootUEFI)) } catch { Write-Output "Secure Boot: not supported/disabled (good)" }
Write-Output ("Test signing: " + ((bcdedit /enum '{current}') -match 'testsigning\s+Yes').Count)
Write-Output ("OS build: " + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild + "." + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)
