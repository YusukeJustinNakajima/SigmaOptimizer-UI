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

$detectStatus = $false
$hits = 0

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

try {
    $hayabusaOutput = & $hayabusa $arg 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Hayabusa execution failed with exit code: $LASTEXITCODE"
        $result = [pscustomobject]@{
            Success  = $false
            HitNum   = 0
            Error    = "Hayabusa execution failed"
        }
        $result | ConvertTo-Json -Compress
        exit 1
    }
    
    $ansiPattern = "(\x1B\[[0-9;]*[A-Za-z])"
    $cleanOutput = $hayabusaOutput -replace $ansiPattern, ""
    $lines = $cleanOutput -split "`n"
    
    Write-Host "Hayabusa output lines count: $($lines.Count)" -ForegroundColor Yellow
    
    $patternLine = "(?i)Events\s+with\s+hits\s*/\s*Total\s+events:"
    $targetLine = $lines | Where-Object { $_ -imatch $patternLine }
    
    if ($targetLine) {
        Write-Host "Target line found: $targetLine" -ForegroundColor Green
        
        # Pattern 1: "Events with hits / Total events: 5 / 100"
        if ($targetLine -imatch "(?i)Events\s+with\s+hits\s*/\s*Total\s+events:\s*(\d+)\s*/\s*(\d+)") {
            $hits = [int]$matches[1]
            $totalEvents = [int]$matches[2]
            
            $detectStatus = $hits -ge 1
            
            Write-Host "Hits: $hits, Total Events: $totalEvents" -ForegroundColor Cyan
        }

        elseif ($targetLine -imatch "(?i)Events\s+with\s+hits:\s*(\d+)") {
            $hits = [int]$matches[1]
            $cov = [math]::Floor($hits / 2.5) 
            $detectStatus = $hits -ge 1
            
            Write-Host "Hits: $hits" -ForegroundColor Cyan
        }
        else {
            Write-Warning "Target line found but pattern didn't match: $targetLine"
        }
    }
    else {
        Write-Warning "No matching line found in Hayabusa output"
        
        Write-Host "First 10 lines of output:" -ForegroundColor Yellow
        $lines | Select-Object -First 10 | ForEach-Object { Write-Host $_ }
        
        Write-Host "Last 10 lines of output:" -ForegroundColor Yellow
        $lines | Select-Object -Last 10 | ForEach-Object { Write-Host $_ }
    }
    
    if (Test-Path $outFile) {
        Copy-Item -Path $outFile -Destination "$PSScriptRoot\..\public\detection_result.csv" -Force
        Write-Host "CSV file copied successfully" -ForegroundColor Green
    }
    else {
        Write-Warning "Output CSV file not found: $outFile"
    }
    
    $result = [pscustomobject]@{
        Success  = $detectStatus
        HitNum   = $hits
    }
    
    Write-Host "Final result: Success=$detectStatus, HitNum=$hits" -ForegroundColor Magenta
    
    $result | ConvertTo-Json -Compress
}
catch {
    Write-Error "An error occurred: $_"
    $result = [pscustomobject]@{
        Success  = $false
        HitNum   = 0
        Error    = $_.Exception.Message
    }
    $result | ConvertTo-Json -Compress
    exit 1
}