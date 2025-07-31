# generateSigmaRules.ps1
# Simple version with Insert-MissingTags for single rule generation

. "$PSScriptRoot\helpers\common.ps1"

function Process-SingleSigmaRule {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SigmaOutput
    )

    if ($SigmaOutput -match "API Request Error" -or $SigmaOutput -match "Failed to generate") {
        throw "API Error: $SigmaOutput"
    }
    
    $SigmaOutput = $SigmaOutput -replace '```yaml\s*', ''
    $SigmaOutput = $SigmaOutput -replace '```\s*$', ''
    $SigmaOutput = $SigmaOutput.Trim()
    
    $lines = $SigmaOutput -split "`n"
    
    $hasAuthor = $false
    $hasDate = $false
    $hasId = $false
    
    foreach ($line in $lines) {
        if ($line -match "^\s*author:") { $hasAuthor = $true }
        if ($line -match "^\s*date:") { $hasDate = $true }
        if ($line -match "^\s*id:") { $hasId = $true }
    }
    
    if (-not $hasAuthor -or -not $hasDate -or -not $hasId) {
        $processedLines = Insert-MissingTags -RuleBlock $lines -HasAuthor $hasAuthor -HasDate $hasDate
        return $processedLines -join "`n"
    } else {
        return $SigmaOutput
    }
}

try {
    $finalLogPath = Join-Path $PSScriptRoot 'final_log.txt'
    if (-not (Test-Path $finalLogPath)) {
        throw "final_log.txt not found at: $finalLogPath"
    }
    
    $finalLog = Get-Content -Path $finalLogPath -Raw -ErrorAction Stop
    
    <#
    $maxLogSize = 10000
    if ($finalLog.Length -gt $maxLogSize) {
        Write-Warning "Log truncated from $($finalLog.Length) to $maxLogSize characters"
        $finalLog = $finalLog.Substring(0, $maxLogSize)
    }
    #>
    
    Write-Verbose "Generating Sigma rule..."
    $sigmaOut = New-SigmaRule -evtxLog $finalLog
    
    if (-not $sigmaOut) {
        throw "New-SigmaRule returned null or empty result"
    }

    $ruleText = Process-SingleSigmaRule -SigmaOutput $sigmaOut
    
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $PSScriptRoot 'rules\generate_rules'
    if (-not (Test-Path $dir)) { 
        New-Item -ItemType Directory -Path $dir -Force | Out-Null 
    }
    $rulePath = Join-Path $dir "generated_sigmarule_${timestamp}.yml"
    
    $ruleText | Out-File -FilePath $rulePath -Encoding utf8
    
    [pscustomobject]@{
        Success = $true
        RuleText = $ruleText
        RulePath = $rulePath
    } | ConvertTo-Json -Compress | Write-Output
    
    exit 0
}
catch {
    [pscustomobject]@{
        Success = $false
        Error = $_.Exception.Message
    } | ConvertTo-Json -Compress | Write-Output
    exit 1
}