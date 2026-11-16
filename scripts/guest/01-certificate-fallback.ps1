# Only needed if the driver's install.ps1 fails at "Import-Certificate" with E_ACCESSDENIED (it did when run through the QEMU guest agent as
# SYSTEM). install.ps1 first extracts the test-signing certificate to %TEMP%\vgpu-test.cer; import that file with certutil instead.
# In an interactive elevated PowerShell the stock install.ps1 / setup .exe should not need this (not verified by the author).
$cer = Join-Path $env:TEMP 'vgpu-test.cer'
if (-not (Test-Path $cer)) { throw "$cer not found: run install.ps1 once so it extracts the certificate" }
certutil -addstore -f Root $cer
certutil -addstore -f TrustedPublisher $cer
Write-Output "certificate trusted; now run install.ps1 again (or a copy with the two Import-Certificate lines removed)"
