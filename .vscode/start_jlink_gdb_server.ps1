$ErrorActionPreference = 'Stop'

$existing = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'JLinkGDBServerCL.exe' -and $_.CommandLine -match '-port\s+2331'
}
foreach ($p in $existing) {
    Stop-Process -Id $p.ProcessId -Force
}

$jlink = Get-ChildItem 'C:/Program Files/SEGGER' -Directory -Filter 'JLink*' |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $jlink) {
    throw 'SEGGER J-Link not found in C:/Program Files/SEGGER'
}

$exe = Join-Path $jlink.FullName 'JLinkGDBServerCL.exe'

Write-Host 'Starting J-Link GDB Server on port 2331 (foreground)...'
Write-Host 'Leave this task running. It should show: Waiting for GDB connection...'

& $exe -if SWD -device nRF54L15_M33 -speed 4000 -port 2331 -swoport 2332 -telnetport 2333 -nogui
