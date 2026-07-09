param(
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$exe = Join-Path $repoRoot "build/windows-msvc-vcpkg/$Configuration/econv.exe"
$testDir = Join-Path $repoRoot "build/manual-tests"

if (-not (Test-Path $exe)) {
    throw "econv executable not found: $exe. Run cmake --build --preset windows-debug first."
}

New-Item -ItemType Directory -Force -Path $testDir | Out-Null

$text = "你好, econv!`r`nCafe resume`r`n日本語テスト`r`n"
[System.IO.File]::WriteAllText((Join-Path $testDir "utf8.txt"), $text, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $testDir "utf8-bom.txt"), $text, [System.Text.UTF8Encoding]::new($true))
[System.IO.File]::WriteAllText((Join-Path $testDir "utf16le-bom.txt"), $text, [System.Text.UnicodeEncoding]::new($false, $true))

$gb18030 = [System.Text.Encoding]::GetEncoding("GB18030")
[System.IO.File]::WriteAllText((Join-Path $testDir "gb18030.txt"), $text, $gb18030)

$results = @()

function Add-Result {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail
    )
    $script:results += [pscustomobject]@{
        Test = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

function Invoke-Econv {
    param([string[]]$ArgsList)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $script:exe @ArgsList 2>&1
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = ($output -join "`n")
        }
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

foreach ($case in @(
    @{ Name = "Detect UTF-8"; File = "utf8.txt"; Expected = "encoding: UTF-8" },
    @{ Name = "Detect UTF-8 BOM"; File = "utf8-bom.txt"; Expected = "encoding: UTF-8" },
    @{ Name = "Detect UTF-16LE BOM"; File = "utf16le-bom.txt"; Expected = "encoding: UTF-16LE" },
    @{ Name = "Detect GB18030 with --from"; File = "gb18030.txt"; Expected = "encoding: GB18030"; From = "GB18030" }
)) {
    $argsList = @("--detect-only")
    if ($case.From) {
        $argsList += @("--from", $case.From)
    }
    $argsList += @("-i", (Join-Path $testDir $case.File))

    $run = Invoke-Econv $argsList
    Add-Result $case.Name ($run.ExitCode -eq 0 -and $run.Output.Contains($case.Expected)) $run.Output
}

$utf8Roundtrip = Join-Path $testDir "gb18030-to-utf8.txt"
$run = Invoke-Econv @("-i", (Join-Path $testDir "gb18030.txt"), "-o", $utf8Roundtrip, "--from", "GB18030", "--to", "UTF-8")
$roundtripText = [System.IO.File]::ReadAllText($utf8Roundtrip, [System.Text.UTF8Encoding]::new($false))
Add-Result "Convert GB18030 -> UTF-8" ($run.ExitCode -eq 0 -and $roundtripText -eq $text) "exit=$($run.ExitCode); textMatches=$($roundtripText -eq $text)"

$utf16Roundtrip = Join-Path $testDir "utf16le-to-utf8.txt"
$run = Invoke-Econv @("-i", (Join-Path $testDir "utf16le-bom.txt"), "-o", $utf16Roundtrip, "--to", "UTF-8")
$roundtripText = [System.IO.File]::ReadAllText($utf16Roundtrip, [System.Text.UTF8Encoding]::new($false))
Add-Result "Convert UTF-16LE BOM -> UTF-8" ($run.ExitCode -eq 0 -and $roundtripText -eq $text) "exit=$($run.ExitCode); textMatches=$($roundtripText -eq $text)"

$utf8BomOut = Join-Path $testDir "utf8-emit-bom.txt"
$run = Invoke-Econv @("-i", (Join-Path $testDir "utf8.txt"), "-o", $utf8BomOut, "--to", "UTF-8", "--emit-bom")
$bytes = [System.IO.File]::ReadAllBytes($utf8BomOut)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
Add-Result "Convert UTF-8 -> UTF-8 with BOM" ($run.ExitCode -eq 0 -and $hasBom) "exit=$($run.ExitCode); hasBom=$hasBom"

$lossyOut = Join-Path $testDir "utf8-to-latin1-strict.txt"
$run = Invoke-Econv @("-i", (Join-Path $testDir "utf8.txt"), "-o", $lossyOut, "--to", "ISO-8859-1")
Add-Result "Strict conversion rejects unrepresentable chars" ($run.ExitCode -ne 0 -and $run.Output.Contains("invalid or unconvertible sequence")) "exit=$($run.ExitCode); output=$($run.Output)"

$results | Format-Table -AutoSize

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -gt 0) {
    throw "$($failed.Count) test(s) failed"
}

Write-Host "All tests passed. Test files: $testDir"
