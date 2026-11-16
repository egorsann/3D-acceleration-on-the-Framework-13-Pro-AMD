# Make wgpu-based programs (AMS Studio, View Studio-style Rust apps) use OpenGL (Mesa zink on Venus) instead of Vulkan.
# The default Vulkan path of such programs crashes inside vulkan_virtio.dll (abort 0x40000015) with driver 1.0.26313.18562,
# the OpenGL path works well. Machine-wide; programs started from an already-running Explorer need Explorer restarted or a re-login.
# Undo: setx /M WGPU_BACKEND ""  and  reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v WGPU_BACKEND /f
setx /M WGPU_BACKEND opengl | Out-Null
Write-Output ("WGPU_BACKEND = " + [Environment]::GetEnvironmentVariable('WGPU_BACKEND','Machine'))
