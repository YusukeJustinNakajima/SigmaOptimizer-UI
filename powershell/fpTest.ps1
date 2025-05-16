# fpTest.ps1
param(
    [Parameter(Mandatory)][string]$RulePath,
    [string]$LogDir = "$PSScriptRoot\benign_evtx_logs"
)

. "$PSScriptRoot\helpers\common.ps1" -NoModule

$hayabusa = "$PSScriptRoot\hayabusa.exe"
$LogDir = "$PSScriptRoot\benign_evtx_logs"
$outFile  = "$PSScriptRoot\fp_check_result.csv"

Write-Host "$hayabusa"
Write-Host "$LogDir"
Write-Host "$outFile"

$arg = @(
  "csv-timeline",
  "--no-wizard",
  "--enable-all-rules",
  "--rules",$RulePath,
  "--directory",$LogDir,
  "--clobber",
  "--output",$outFile
)

Write-Host "$arg"

$hayabusaOutput = & $hayabusa $arg 2>&1
$ansiPattern = "(\x1B\[[0-9;]*[A-Za-z])"
$cleanOutput = $hayabusaOutput -replace $ansiPattern, ""
$lines = $cleanOutput -split "`n"
$patternLine = "(?i)Events\s+with\s+hits\s*/\s*Total\s+events:"
$targetLine = $lines | Where-Object { $_ -imatch $patternLine }
Write-Host "$outtargetLine"

<#
if ($LASTEXITCODE -ne 0) { 
    return @{ Status="ERR"; Hits=-1 } 
}
#>

if ($targetLine) {
    if  ($targetLine -imatch "(?i)Events\s+with\s+hits\s*/\s*Total\s+events:\s*(\d+)\s*/") {
        $hits = [int]$matches[1]
        $cov  = [math]::Floor($hits / 2.5)

        if ($hits -ge 1) {
            $detectStatus = $false
        } else {
            $detectStatus = $true
        }
    }
}

Copy-Item -Path "$PSScriptRoot\fp_check_result.csv" -Destination "$PSScriptRoot\..\public\fp_check_result.csv"

$result = [pscustomobject]@{
    Success  = $detectStatus
    Coverage = $cov
    HitNum   = $hits
}

$result | ConvertTo-Json -Compress