# powershell\syntaxTest.ps1
param(
    [Parameter(Mandatory=$true)] [string]$RuleFilePath
)

# ---- 余計なメッセージ抑止 ----
$WarningPreference     = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
# -----------------------------

. "$PSScriptRoot/helpers/common.ps1"

$full = (Resolve-Path $RuleFilePath).Path
$result = [pscustomobject]@{
    Success = $false
    Rule    = $full
    Message = ""
}

try {
    $ok = Invoke-SigmaRuleTests -SpecificFile $full -ErrorAction Stop
    
    if ($ok) {
        $result.Success = $true
        $result.Message = 'Syntax test passed'
    } else {
        $result.Message = 'Syntax test failed'
    }
} catch {
    $result.Message = $_.Exception.Message
}

$result | ConvertTo-Json -Compress

# ④ ExitCode: 0 = pass, 1 = fail
exit ([int](!$result.Success))