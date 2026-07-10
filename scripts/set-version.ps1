param(
    [Parameter(Position = 0)]
    [int]$Major = -1,
    [Parameter(Position = 1)]
    [int]$Minor = -1,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$cmakeFile = Join-Path $repoRoot "CMakeLists.txt"
$vcpkgFile = Join-Path $repoRoot "vcpkg.json"

function Get-CurrentVersion {
    param([string]$Text)
    $m = [regex]::Match($Text, '(?m)^\s*project\s*\(\s*econv\s+VERSION\s+(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?\s+LANGUAGES\s+CXX\s*\)')
    if (-not $m.Success) { throw 'Could not find project version in CMakeLists.txt' }
    [pscustomobject]@{
        Major = [int]$m.Groups[1].Value
        Minor = [int]$m.Groups[2].Value
        Patch = if ($m.Groups[3].Value) { [int]$m.Groups[3].Value } else { 0 }
        Date  = if ($m.Groups[4].Value) { [int]$m.Groups[4].Value } else { 0 }
    }
}

$cmakeText = Get-Content $cmakeFile -Raw
$current = Get-CurrentVersion $cmakeText

if ($Major -lt 0 -or $Minor -lt 0) {
    Write-Host "Current version: $($current.Major).$($current.Minor).$($current.Patch).$($current.Date)"
}
if ($Major -lt 0) {
    $majorInput = Read-Host 'Major version'
    if ($majorInput -notmatch '^\d+$') { throw 'Invalid major version' }
    $Major = [int]$majorInput
}
if ($Minor -lt 0) {
    $minorInput = Read-Host 'Minor version'
    if ($minorInput -notmatch '^\d+$') { throw 'Invalid minor version' }
    $Minor = [int]$minorInput
}

$today = Get-Date
$year = $today.Year
$datePart = $today.Month * 100 + $today.Day
$dotVersion = "$Major.$Minor.$year.$datePart"

Write-Host "Current version: $($current.Major).$($current.Minor).$($current.Patch).$($current.Date)"
Write-Host "New version: $dotVersion"

if ($DryRun) {
    Write-Host 'Dry run: no files changed.'
    exit 0
}

# Update CMakeLists.txt
$cmakeText = [regex]::Replace($cmakeText,
    '(?m)^(\s*project\s*\(\s*econv\s+VERSION\s+)\d+\.\d+\.\d+(?:\.\d+)?(\s+LANGUAGES\s+CXX\s*\))',
    { param($m) $m.Groups[1].Value + $dotVersion + $m.Groups[2].Value })
Set-Content -Path $cmakeFile -Value $cmakeText -NoNewline

# Update vcpkg.json
$vcpkgText = Get-Content $vcpkgFile -Raw
$vcpkgText = [regex]::Replace($vcpkgText,
    '(?m)("(?:version-string|version)"\s*:\s*")[^"]*(")',
    { param($m) $m.Groups[1].Value + $dotVersion + $m.Groups[2].Value })
Set-Content -Path $vcpkgFile -Value $vcpkgText -NoNewline

Write-Host "Updated: CMakeLists.txt, vcpkg.json"
