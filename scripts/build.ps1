param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not $env:VCPKG_ROOT) {
    $vsVcpkg = "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\vcpkg"
    if (Test-Path $vsVcpkg) {
        $env:VCPKG_ROOT = $vsVcpkg
    } else {
        throw "VCPKG_ROOT not set and VS bundled vcpkg not found."
    }
}

$presetName = if ($Configuration -eq 'Debug') { 'windows-debug' } else { 'windows-release' }

Write-Host "Configuring (preset: windows-msvc-vcpkg)..."
& cmake --preset windows-msvc-vcpkg
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Rebuild) {
    Write-Host "Cleaning and building ($Configuration)..."
    & cmake --build --preset $presetName --clean-first
} else {
    Write-Host "Building ($Configuration)..."
    & cmake --build --preset $presetName
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$exe = Join-Path $repoRoot "build/windows-msvc-vcpkg/$Configuration/econv.exe"
if (Test-Path $exe) {
    Write-Host "Build output: $exe"
    Get-FileHash $exe -Algorithm MD5 | Format-Table -AutoSize
} else {
    Write-Warning "Build finished, but output was not found: $exe"
}
