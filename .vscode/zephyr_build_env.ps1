$ErrorActionPreference = 'Stop'

# Join-Path / GetFullPath 는 드라이브가 없으면(e.g. E: 미연결) 예외를 낼 수 있어,
# SDK 루트만 문자열로 이어 붙입니다. 실존 검사는 Test-Path 로만 합니다.

function Normalize-SdkPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $s = [string]$Path.Trim() -replace '\\', '/' -replace '//+', '/'
    return $s.TrimEnd('/')
}

function Combine-SdkPath([string]$Base, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Base)) {
        return (Normalize-SdkPath $Relative).TrimStart('/')
    }
    $b = (Normalize-SdkPath $Base).TrimEnd('/')
    $r = (Normalize-SdkPath $Relative).TrimStart('/')
    return "$b/$r"
}

function Test-WindowsDriveReady([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $p = Normalize-SdkPath $Path
    if (($PSVersionTable.PSVersion.Platform -ne 'Unix') -and ($p.Length -ge 2) -and ($p[1] -eq ':')) {
        $letter = [string][char]::ToUpperInvariant($p[0])
        try {
            $di = New-Object System.IO.DriveInfo($letter)
            return $di.IsReady
        }
        catch {
            return $false
        }
    }
    return $true
}

function Test-ZephyrDefaultModulePresent([string]$NrfBmRoot) {
    if ([string]::IsNullOrWhiteSpace($NrfBmRoot)) { return $false }
    $zep = Combine-SdkPath $NrfBmRoot 'zephyr/cmake/modules/zephyr_default.cmake'
    return Test-Path -LiteralPath $zep
}

function Resolve-NrfBmHome {
    param(
        [string]$NcsHome,
        [string]$PreferPath = 'E:/ncs/nrf-bm/v1.0.0'
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($src in @(
            $env:NRF_BM_HOME
            $PreferPath
            (Combine-SdkPath $NcsHome 'nrf-bm/v1.0.0')
            'C:/ncs/nrf-bm/v1.0.0'
        )) {
        if ([string]::IsNullOrWhiteSpace($src)) { continue }
        $norm = Normalize-SdkPath $src
        if ((-not $norm) -or (-not (Test-WindowsDriveReady $norm))) { continue }
        if (-not $candidates.Contains($norm)) { $candidates.Add($norm) }
    }

    foreach ($cand in $candidates) {
        if (Test-ZephyrDefaultModulePresent $cand) {
            return $cand
        }
    }

    return $null
}

function Resolve-ExistingSdkPath([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "경로가 없습니다: $Path"
    }
    return (Normalize-SdkPath ([System.IO.Path]::GetFullPath($Path)))
}

function Get-NrfToolchainRoot {
    param([string]$NcsHome, [string]$NcsVersion = 'v2.7.0')

    if ($env:NCS_TOOLCHAIN_ROOT -and (Test-Path -LiteralPath $env:NCS_TOOLCHAIN_ROOT)) {
        return (Resolve-ExistingSdkPath $env:NCS_TOOLCHAIN_ROOT)
    }

    $tf = Combine-SdkPath $NcsHome 'toolchains/toolchains.json'
    if (Test-Path -LiteralPath $tf) {
        try {
            $doc = Get-Content -LiteralPath $tf -Raw | ConvertFrom-Json
            $rootEntry = @($doc)[0]
            $bundle = @(
                $rootEntry.toolchains |
                    Where-Object { $_.ncs_versions -contains $NcsVersion } |
                    Select-Object -First 1
            )
            if ($bundle) {
                $bid = $bundle.identifier.bundle_id
                $tr = Combine-SdkPath $NcsHome "toolchains/$bid"
                $ninja = Combine-SdkPath $tr 'opt/bin/ninja.exe'
                if (Test-Path -LiteralPath $ninja) {
                    return (Normalize-SdkPath $tr)
                }
            }
        }
        catch { }
    }

    foreach ($guess in @('fd21892d0f', 'ce3b5ff664', 'c1a76fddb2')) {
        $tr = Combine-SdkPath $NcsHome "toolchains/$guess"
        $ninja = Combine-SdkPath $tr 'opt/bin/ninja.exe'
        if (Test-Path -LiteralPath $ninja) {
            return (Normalize-SdkPath $tr)
        }
    }

    throw @"
Zephyr 툴체인(Ninja/Python/SDK) 폴더를 찾을 수 없습니다.

  NCS_HOME: $NcsHome  (실제 설치 드라이브에 맞게 `$env:NCS_HOME` 설정)

예: `$env:NCS_HOME = 'C:/ncs'` 또는 **`E:` 장치가 안 보일 때**(USB 미연결/다른 PC) 실제 존재하는 경로를 지정하세요.
  `$env:NCS_TOOLCHAIN_ROOT` = '<존재하는 경로>/toolchains/<bundle_id>`
  `$env:NCS_VERSION` 은 toolchains.json 의 ncs_versions 와 같아야 합니다 (기본 v2.7.0).
"@
}

if ([string]::IsNullOrWhiteSpace($env:NCS_HOME)) {
    foreach ($trial in @('E:/ncs', 'C:/ncs')) {
        if (-not (Test-WindowsDriveReady $trial)) { continue }
        if (Test-Path -LiteralPath (Combine-SdkPath $trial 'toolchains')) {
            $env:NCS_HOME = $trial
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($env:NCS_HOME)) {
    $env:NCS_HOME = 'C:/ncs'
}
$NcsHome = Normalize-SdkPath $env:NCS_HOME

$resolvedBm = Resolve-NrfBmHome -NcsHome $NcsHome
if (-not $resolvedBm) {
    $nrfEnvDbg = if ([string]::IsNullOrWhiteSpace($env:NRF_BM_HOME)) { '(미설정)' } else { $env:NRF_BM_HOME }
    $msgIntro = @"

nrf-bm Zephyr를 표준 후보 경로 어디에서도 찾지 못했습니다.

시도 순서(드라이브가 준비된 경우만):
  `$env:NRF_BM_HOME` 환경 값 → E:/ncs/nrf-bm/v1.0.0 → $($NcsHome)/nrf-bm/v1.0.0 → C:/ncs/nrf-bm/v1.0.0

각 경로에는 zephyr/cmake/modules/zephyr_default.cmake 파일이 있어야 합니다.

  NCS_HOME(적용값)=$NcsHome , NRF_BM_HOME(환경·참조용)=$nrfEnvDbg

직접 지정 예: `$env:NRF_BM_HOME = '<실제 nrf-bm v1 부모 폴더>'
"@
    throw $msgIntro
}

$env:NRF_BM_HOME = $resolvedBm
$NrfBmHome = Normalize-SdkPath $resolvedBm
$ncsVer = if ($env:NCS_VERSION) { $env:NCS_VERSION } else { 'v2.7.0' }
$toolchainRoot = Get-NrfToolchainRoot -NcsHome $NcsHome -NcsVersion $ncsVer

$ZephyrBuildPythonExe = Combine-SdkPath $toolchainRoot 'opt/bin/python.exe'
$ZephyrBuildNinjaExe = Combine-SdkPath $toolchainRoot 'opt/bin/ninja.exe'
$ZephyrBuildSdkDir = Combine-SdkPath $toolchainRoot 'opt/zephyr-sdk'

foreach ($exe in @($ZephyrBuildPythonExe, $ZephyrBuildNinjaExe)) {
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "툴체인 번들에 필요한 실행 파일이 없습니다: $exe"
    }
}

$env:ZEPHYR_BASE = (Combine-SdkPath $NrfBmHome 'zephyr')
$env:ZEPHYR_TOOLCHAIN_VARIANT = 'zephyr'
$env:ZEPHYR_SDK_INSTALL_DIR = $ZephyrBuildSdkDir

$toolBin = Combine-SdkPath $toolchainRoot 'opt/bin'
if ($IsWindows -or ($PSVersionTable.PSVersion.Platform -eq 'Win32NT')) {
    $toolBinWin = $toolBin -replace '/', '\'
    $env:PATH = "$toolBinWin;$($env:PATH)"
} else {
    $env:PATH = "${toolBin}:$($env:PATH)"
}

$ZephyrBuildBoardRoot = Combine-SdkPath $NrfBmHome 'nrf-bm'
$ZephyrBuildExtraModules = $ZephyrBuildBoardRoot
$ZephyrBuildSdHex = Combine-SdkPath $ZephyrBuildBoardRoot 'components/softdevice/s145/s145_nrf54l15_9.0.0_softdevice.hex'
$ZephyrBuildObjcopy = Combine-SdkPath $ZephyrBuildSdkDir 'arm-zephyr-eabi/bin/arm-zephyr-eabi-objcopy.exe'
$ZephyrBuildGdb = Combine-SdkPath $ZephyrBuildSdkDir 'arm-zephyr-eabi/bin/arm-zephyr-eabi-gdb.exe'
