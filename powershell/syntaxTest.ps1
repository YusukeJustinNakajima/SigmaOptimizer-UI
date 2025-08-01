param(
    [Parameter(Mandatory=$true)] [string]$RuleFilePath
)

# ---- 余計なメッセージ抑止 ----
$ErrorActionPreference = 'Stop'
$WarningPreference     = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
# -----------------------------

. "$PSScriptRoot/helpers/common.ps1"

$full = (Resolve-Path $RuleFilePath -ErrorAction SilentlyContinue).Path
if (-not $full) {
    $result = [pscustomobject]@{
        Success = $false
        Message = "Rule file not found: $RuleFilePath"
        Details = ""
    }
    $result | ConvertTo-Json -Compress
    exit 1
}

$result = [pscustomobject]@{
    Success = $false
    Rule    = $full
    Message = ""
    Details = ""
}

try {
    # リダイレクトしてエラーをキャプチャ
    $testOutput = & {
        $ErrorActionPreference = 'Continue'
        Invoke-SigmaRuleTests -SpecificFile $full 2>&1
    }
    
    if ($testOutput.Success) {
        $result.Success = $true
        $result.Message = 'All syntax tests passed'
    } else {
        $result.Success = $false
        $result.Message = "Syntax validation failed: $($testOutput.FailedCount) test(s) failed"
        
        # エラーメッセージを人間が読みやすい形式に
        if ($testOutput.ErrorMessages) {
            $result.Details = $testOutput.ErrorMessages
        } else {
            $result.Details = "Failed tests detected but no specific error messages available"
        }
    }
} catch {
    # より読みやすいエラーメッセージ
    $result.Success = $false
    $result.Message = "Test execution failed"
    $result.Details = "Error: $($_.Exception.Message)"
}

$result | ConvertTo-Json -Compress -Depth 10

exit ([int](!$result.Success))