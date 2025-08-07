# generateSigmaRules.ps1
param(
    [string]$Provider = $env:AI_PROVIDER,
    [string]$Model = $env:AI_MODEL
)

. "$PSScriptRoot\helpers\common.ps1"

Import-Module "$PSScriptRoot\LLM_SigmaModule.psm1" -Force

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
    
    Write-Verbose "Generating Sigma rule with $Provider..."
    
    if ($Model) {
        $sigmaOut = New-SigmaRule -evtxLog $finalLog -Provider $Provider -model $Model
    } else {
        $sigmaOut = New-SigmaRule -evtxLog $finalLog -Provider $Provider
    }
    
    if (-not $sigmaOut) {
        throw "New-SigmaRule returned null or empty result"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($rulePath, $ruleText, $utf8NoBom)
    
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
        Provider = $Provider
        Model = if ($Model) { $Model } else { "default" }
    } | ConvertTo-Json -Compress | Write-Output
    
    exit 0
}
catch {
    [pscustomobject]@{
        Success = $false
        Error = $_.Exception.Message
        Provider = $Provider
    } | ConvertTo-Json -Compress | Write-Output
    exit 1
}
