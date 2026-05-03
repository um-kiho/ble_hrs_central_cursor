$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'zephyr_build_env.ps1')

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$elf = Join-Path $workspace 'build/zephyr/zephyr.elf'
$gdb = $ZephyrBuildGdb

$jlinkDir = Get-ChildItem 'C:/Program Files/SEGGER' -Directory -Filter 'JLink*' |
    Sort-Object Name -Descending |
    Select-Object -First 1
if (-not $jlinkDir) {
    throw 'SEGGER J-Link not found in C:/Program Files/SEGGER'
}
$jlink = Join-Path $jlinkDir.FullName 'JLinkGDBServerCL.exe'

if (-not (Test-Path $elf)) {
    throw "ELF not found: $elf"
}

$probe = Test-NetConnection -ComputerName '127.0.0.1' -Port 2331 -WarningAction SilentlyContinue
if (-not $probe.TcpTestSucceeded) {
    Start-Process -FilePath $jlink -ArgumentList @(
        '-if', 'SWD',
        '-device', 'nRF54L15_M33',
        '-speed', '4000',
        '-port', '2331',
        '-swoport', '2332',
        '-telnetport', '2333',
        '-nogui'
    ) -WindowStyle Minimized

    Start-Sleep -Seconds 1
}

$maxRetries = 20
$ready = $false
for ($i = 0; $i -lt $maxRetries; $i++) {
    $probe = Test-NetConnection -ComputerName '127.0.0.1' -Port 2331 -WarningAction SilentlyContinue
    if ($probe.TcpTestSucceeded) {
        $ready = $true
        break
    }
    Start-Sleep -Milliseconds 250
}

if (-not $ready) {
    throw 'J-Link GDB server is not reachable on port 2331'
}

Write-Host 'Starting GDB attach session (CLI)...'
& $gdb -q $elf `
    -ex "set pagination off" `
    -ex "target remote localhost:2331" `
    -ex "monitor reset" `
    -ex "monitor halt" `
    -ex "thbreak main" `
    -ex "continue"
