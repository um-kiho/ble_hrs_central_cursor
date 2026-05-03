$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'zephyr_build_env.ps1')

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildDir = Join-Path $workspace 'build'

cmake -S $workspace -B $buildDir -G Ninja `
  "-DCMAKE_MAKE_PROGRAM:FILEPATH=$ZephyrBuildNinjaExe" `
  "-DPython3_EXECUTABLE:STRING=$ZephyrBuildPythonExe" `
  "-DSD_HEX:STRING=$ZephyrBuildSdHex" `
  -DBOARD:STRING=bm_nrf54l15dk/nrf54l15/cpuapp/s145_softdevice `
  "-DBOARD_ROOT:PATH=$ZephyrBuildBoardRoot" `
  "-DZEPHYR_EXTRA_MODULES:STRING=$ZephyrBuildExtraModules" `
  -DZEPHYR_TOOLCHAIN_VARIANT:STRING=zephyr `
  "-DZEPHYR_SDK_INSTALL_DIR:STRING=$ZephyrBuildSdkDir"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nCMake configure 실패입니다. nrf-bm에서 west update 필요 여부를 확인하세요." -ForegroundColor Red
    exit $LASTEXITCODE
}

cmake --build $buildDir --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nCMake build 실패; Flash 크기 요약은 생략합니다." -ForegroundColor Red
    exit $LASTEXITCODE
}

# --- App + SoftDevice size summary ---
$appBin = Join-Path $buildDir 'zephyr/zephyr.bin'
$sdHex = $ZephyrBuildSdHex
$totalFlash = 1524

$appSize = 0
if (Test-Path $appBin) { $appSize = (Get-Item $appBin).Length }
$appKB = [math]::Round($appSize / 1024, 1)

$sdSize = 0
if (Test-Path $sdHex) {
    $objcopy = $ZephyrBuildObjcopy
    $sdBinTmp = "$env:TEMP/sd_size_check.bin"
    & $objcopy --input-target=ihex --output-target=binary $sdHex $sdBinTmp 2>$null
    if (Test-Path $sdBinTmp) {
        $sdSize = (Get-Item $sdBinTmp).Length
        Remove-Item $sdBinTmp -Force -ErrorAction SilentlyContinue
    }
}
$sdKB = [math]::Round($sdSize / 1024, 1)

$combinedSize = $appSize + $sdSize
$combinedKB = [math]::Round($combinedSize / 1024, 1)
$pct = [math]::Round($combinedSize / ($totalFlash * 1024) * 100, 2)

Write-Host ''
Write-Host '========== Flash Size Summary ==========' -ForegroundColor Cyan
Write-Host ("  App (zephyr.bin)  : {0,8:N0} B  ({1} KB)" -f $appSize, $appKB)
Write-Host ("  SoftDevice (s145) : {0,8:N0} B  ({1} KB)" -f $sdSize, $sdKB)
Write-Host ("  ----------------------------------------")
Write-Host ("  Total             : {0,8:N0} B  ({1} KB)  [{2}% of {3} KB]" -f $combinedSize, $combinedKB, $pct, $totalFlash) -ForegroundColor Yellow
Write-Host '========================================' -ForegroundColor Cyan
