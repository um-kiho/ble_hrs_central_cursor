$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'zephyr_build_env.ps1')

# PATH에 west 명령이 없어도 NCS 번들 Python으로 동일하게 동작합니다.
$py = $ZephyrBuildPythonExe

$zephyrDir = Combine-SdkPath $NrfBmHome 'zephyr'
if (-not (Test-Path -LiteralPath $zephyrDir)) {
    throw "Zephyr 디렉터리가 없습니다: $zephyrDir"
}

Push-Location $zephyrDir
try {
    Write-Host "west topdir 실행 (Python: $py)" -ForegroundColor DarkGray
    $westOut = & $py -m west topdir 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "west topdir 실패 ($LASTEXITCODE): $($westOut | Out-String)"
    }
    $lines = @($westOut | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $wsRoot = $lines | Select-Object -Last 1
    if (-not $wsRoot -or -not (Test-Path -LiteralPath $wsRoot)) {
        throw "west topdir 결과가 유효한 경로가 아닙니다: $wsRoot"
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host "West workspace root: $wsRoot" -ForegroundColor Cyan
Write-Host '(west update — 시간이 걸리고 네트워크가 필요합니다.)' -ForegroundColor DarkYellow
Write-Host ''

Push-Location $wsRoot
try {
    & $py -m west update @args
    if ($LASTEXITCODE -ne 0) {
        throw "west update 종료 코드: $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'west update 완료. 프로젝트에서 Clean Rebuild 를 다시 실행하세요.' -ForegroundColor Green
