# detectTest.ps1
param(
    [Parameter(Mandatory)][string]$RulePath,
    [Parameter(Mandatory)][string]$StartTime,
    [Parameter(Mandatory)][string]$EndTime
)

# $ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\helpers\common.ps1" -NoModule

$hayabusa = "$PSScriptRoot\hayabusa.exe"
$LogDir = "$PSScriptRoot\logs"
$outFile  = "$PSScriptRoot\detection_result.csv"

$arg = @(
  "csv-timeline",
  "--no-wizard",
  "--timeline-start", $StartTime,
  "--timeline-end", $EndTime,
  "--enable-all-rules",
  "--rules",$RulePath,
  "--directory",$LogDir,
  "--clobber",
  "--output",$outFile
)

Write-Output "StartTime=$StartTime"
Write-Output "EndTime=$EndTime"

$hayabusaOutput = & $hayabusa $arg 2>&1
$ansiPattern = "(\x1B\[[0-9;]*[A-Za-z])"
$cleanOutput = $hayabusaOutput -replace $ansiPattern, ""
$lines = $cleanOutput -split "`n"
$patternLine = "(?i)Events\s+with\s+hits\s*/\s*Total\s+events:"
$targetLine = $lines | Where-Object { $_ -imatch $patternLine }

if ($LASTEXITCODE -ne 0) {
    return @{ Status="ERR"; Coverage=0; Hits=0 }
}

if ($targetLine) {
    if ($targetLine -imatch "(?i)Events\s+with\s+hits\s*/\s*Total\s+events:\s*(\d+)\s*/") {
        $hits = [int]$matches[1]
        $cov  = [math]::Floor($hits / 2.5)

        if ($hits -ge 1) {
            $detectStatus = $true
        } else {
            $detectStatus = $false
        }
    }
}

Copy-Item -Path "$PSScriptRoot\detection_result.csv" -Destination "$PSScriptRoot\..\public\detection_result.csv"

$result = [pscustomobject]@{
    Success  = $detectStatus
    Coverage = $cov
    HitNum   = $hits
}
$result | ConvertTo-Json -Compress
