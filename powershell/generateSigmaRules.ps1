# generateSigmaRules.ps1

. "$PSScriptRoot\helpers\common.ps1"

try {

    $finalLogPath = Join-Path $PSScriptRoot 'final_log.txt'
    $finalLog = Get-Content -Path $finalLogPath -Raw -ErrorAction Stop

    $sigmaOut = New-SigmaRule -evtxLog $finalLog
    $ruleText     = Extract-SigmaRules -SigmaOutput $sigmaOut

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir       = Join-Path $PSScriptRoot 'rules\generate_rules'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $rulePath  = Join-Path $dir "generated_sigmarule_${timestamp}.yml"

    $ruleText | Out-File -FilePath $rulePath -Encoding utf8

    [pscustomobject]@{
        Success  = $true
        RuleText = $ruleText
        RulePath = $rulePath
    } | ConvertTo-Json -Compress | Write-Output

    exit 0
}
catch {
    [pscustomobject]@{
        Success = $false
        Error   = $_.Exception.Message
    } | ConvertTo-Json -Compress | Write-Output
    exit 1
}
