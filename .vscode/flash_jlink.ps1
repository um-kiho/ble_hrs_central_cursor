$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'zephyr_build_env.ps1')

# J-Link USB access is exclusive; stale commander/server processes can cause
# "Out of sync" or timeout errors during flashing.
Get-CimInstance Win32_Process |
    Where-Object { $_.Name -in @('JLink.exe', 'JLinkGDBServerCL.exe') } |
    ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { }
    }
Start-Sleep -Milliseconds 700

$jlinkDir = Get-ChildItem 'C:/Program Files/SEGGER' -Directory -Filter 'JLink*' |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $jlinkDir) {
    throw 'SEGGER J-Link not found'
}

$jlinkExe = Join-Path $jlinkDir.FullName 'JLink.exe'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appHex = Join-Path $workspace 'build/zephyr/zephyr.hex'
$sdHex = $ZephyrBuildSdHex

if (-not (Test-Path $appHex)) {
    throw "App HEX not found: $appHex"
}

if (-not (Test-Path $sdHex)) {
    throw "SoftDevice HEX not found: $sdHex"
}

$jlinkScriptContent = @(
    'device nRF54L15_M33'
    'si swd'
    'speed 4000'
    'r'
    "loadfile $sdHex"
    "loadfile $appHex"
    'r'
    'g'
    'q'
) -join "`n"

$jlinkScriptPath = Join-Path $env:TEMP 'jlink_flash_zephyr.jlink'
Set-Content -Path $jlinkScriptPath -Value $jlinkScriptContent -NoNewline -Encoding ASCII

$attempts = 3
$ok = $false
for ($i = 1; $i -le $attempts; $i++) {
    Write-Host "Flash attempt $i/$attempts..."
    & $jlinkExe -nogui 1 -CommanderScript $jlinkScriptPath
    if ($LASTEXITCODE -eq 0) {
        $ok = $true
        break
    }

    # Reclaim USB probe and retry.
    Get-CimInstance Win32_Process |
        Where-Object { $_.Name -in @('JLink.exe', 'JLinkGDBServerCL.exe') } |
        ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { }
        }
    Start-Sleep -Seconds 1
}

if (-not $ok) {
    throw 'J-Link flashing failed after retries. Reconnect the USB cable or power-cycle the board and try again.'
}
