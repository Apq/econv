param(
    [switch]$SkipRebuild,
    [switch]$KeepStaging,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildScript = Join-Path $PSScriptRoot 'build.ps1'
$buildRoot = Join-Path $repoRoot 'build/windows-msvc-vcpkg'
$releaseDir = Join-Path $buildRoot 'Release'
$installedRoot = Join-Path $buildRoot 'vcpkg_installed/x64-windows'
$distDir = if ($OutputDirectory) {
    [System.IO.Path]::GetFullPath($OutputDirectory, $repoRoot)
} else {
    Join-Path $repoRoot 'dist'
}

function Invoke-Checked {
    param(
        [string]$Description,
        [scriptblock]$Command
    )

    Write-Host "==> $Description"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

function Copy-RequiredFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required file not found: $Source"
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw "Build script not found: $buildScript"
}

$buildParams = @{ Configuration = 'Release' }
if (-not $SkipRebuild) {
    $buildParams.Rebuild = $true
}
Invoke-Checked 'Release build' { & $buildScript @buildParams }

Invoke-Checked 'CTest Release suite' {
    & ctest --test-dir $buildRoot -C Release --output-on-failure
}

$exe = Join-Path $releaseDir 'econv.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Release executable not found: $exe"
}

$versionOutput = (& $exe --version 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '^econv\s+(\d+\.\d+\.\d+\.\d+)\s*$') {
    throw "Could not determine release version from econv.exe: $versionOutput"
}
$version = $Matches[1]

$cmakeText = Get-Content (Join-Path $repoRoot 'CMakeLists.txt') -Raw
if ($cmakeText -notmatch '(?m)^\s*project\s*\(\s*econv\s+VERSION\s+([^\s\)]+)') {
    throw 'Could not determine version from CMakeLists.txt'
}
$cmakeVersion = $Matches[1]

$vcpkgManifest = Get-Content (Join-Path $repoRoot 'vcpkg.json') -Raw | ConvertFrom-Json
$vcpkgVersion = $vcpkgManifest.'version-string'
if ($version -ne $cmakeVersion -or $version -ne $vcpkgVersion) {
    throw "Version mismatch: exe=$version, CMake=$cmakeVersion, vcpkg=$vcpkgVersion"
}

$packageName = "econv-$version-windows-x64"
$stagingDir = Join-Path $distDir $packageName
$zipPath = Join-Path $distDir "$packageName.zip"
$zipChecksumPath = "$zipPath.sha256"

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
if (Test-Path -LiteralPath $zipChecksumPath) {
    Remove-Item -LiteralPath $zipChecksumPath -Force
}

New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Write-Host "==> Collecting release files"
Copy-RequiredFile $exe $stagingDir
Copy-RequiredFile (Join-Path $releaseDir 'iconv-2.dll') $stagingDir
Copy-RequiredFile (Join-Path $releaseDir 'uchardet.dll') $stagingDir
Copy-RequiredFile (Join-Path $repoRoot 'README.md') $stagingDir
Copy-RequiredFile (Join-Path $repoRoot 'LICENSE') (Join-Path $stagingDir 'LICENSE.txt')
Copy-RequiredFile (Join-Path $repoRoot 'THIRD-PARTY-NOTICES.md') $stagingDir

$uchardetLicensePath = Join-Path $installedRoot 'share/uchardet/copyright'
$libiconvLicensePath = Join-Path $installedRoot 'share/libiconv/copyright'
if (-not (Test-Path -LiteralPath $uchardetLicensePath -PathType Leaf)) {
    throw "uchardet license file not found: $uchardetLicensePath"
}
if (-not (Test-Path -LiteralPath $libiconvLicensePath -PathType Leaf)) {
    throw "libiconv license file not found: $libiconvLicensePath"
}

$thirdPartyLicenses = @(
    'THIRD-PARTY LICENSES',
    '====================',
    '',
    'uchardet 0.0.8',
    'Source: https://gitlab.freedesktop.org/uchardet/uchardet',
    '----------------',
    (Get-Content -LiteralPath $uchardetLicensePath -Raw),
    '',
    'GNU libiconv 1.19',
    'Source: https://git.savannah.gnu.org/git/libiconv.git',
    '-----------------',
    (Get-Content -LiteralPath $libiconvLicensePath -Raw)
) -join "`n"
[System.IO.File]::WriteAllText(
    (Join-Path $stagingDir 'THIRD-PARTY-LICENSES.txt'),
    $thirdPartyLicenses,
    [System.Text.UTF8Encoding]::new($false))

$requirements = @"
econv $version - Windows x64

Runtime requirements:
- Windows x64
- Microsoft Visual C++ Redistributable compatible with the MSVC toolset used to build this package

The package includes the required uchardet and GNU libiconv DLLs.
"@
[System.IO.File]::WriteAllText(
    (Join-Path $stagingDir 'REQUIREMENTS.txt'),
    $requirements,
    [System.Text.UTF8Encoding]::new($false))

Invoke-Checked 'Packaged executable smoke check' {
    & (Join-Path $stagingDir 'econv.exe') --version
}

Write-Host "==> Creating ZIP package"
Compress-Archive -LiteralPath $stagingDir -DestinationPath $zipPath -CompressionLevel Optimal

$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText(
    $zipChecksumPath,
    "$zipHash  $([System.IO.Path]::GetFileName($zipPath))`n",
    [System.Text.UTF8Encoding]::new($false))

$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $expectedEntries = @(
        "$packageName/econv.exe",
        "$packageName/iconv-2.dll",
        "$packageName/uchardet.dll",
        "$packageName/LICENSE.txt",
        "$packageName/THIRD-PARTY-NOTICES.md",
        "$packageName/THIRD-PARTY-LICENSES.txt",
        "$packageName/REQUIREMENTS.txt"
    )
    $archiveEntries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    foreach ($entry in $expectedEntries) {
        if ($archiveEntries -notcontains $entry) {
            throw "ZIP validation failed; missing entry: $entry"
        }
    }
    $forbiddenEntries = @(
        "$packageName/SHA256SUMS.txt",
        "$packageName/docs/",
        "$packageName/licenses/"
    )
    foreach ($entry in $forbiddenEntries) {
        if ($archiveEntries | Where-Object { $_.StartsWith($entry) }) {
            throw "ZIP validation failed; forbidden entry found: $entry"
        }
    }
} finally {
    $archive.Dispose()
}

if (-not $KeepStaging) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
}

Write-Host "Release package created: $zipPath"
Write-Host "SHA-256: $zipHash"
Write-Host "Checksum file: $zipChecksumPath"
