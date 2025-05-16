# main.ps1
[CmdletBinding()]
param(
    [string]$Mode        = "cmd",       # cmd / ps / cal
    [string]$Command     = ""
)

. "$PSScriptRoot\helpers\common.ps1"

# 1) コマンド実行・EVTX 収集（元スクリプトの前半部をそのまま）
#    - $finalLog に最終ログを作成
#    - $startTime, $endTime を確定
# -------------------------------------------------------------

# 2) Sigma ルール生成ループ
$iteration = 1
$maxIter   = 1
$coverage  = 0
$results   = @()

$logCollectResult = & "$PSScriptRoot\logCollector.ps1" -Mode $Mode -Command $Command
$startTime = $logCollectResult.startTime
$endTime = $logCollectResult.endTime

Write-Host "$startTime"
Write-Host "$endTime"

$script:finalLog = Get-Content -Path ".\final_log.txt" -Raw

while ($iteration -le $maxIter) {
    
    $sigmaOut = if ($iteration -eq 1) {
        New-SigmaRule -evtxLog $finalLog
    } else {
        # 過去結果を踏まえて再生成
        New-SigmaRule -evtxLog $finalLog -Iteration $iteration
    }

    Write-Output "$sigmaOut"
    $rules = Extract-SigmaRules -SigmaOutput $sigmaOut
    $idx   = 1
    Write-Output "$idx"
    foreach ($rule in $rules) {
        # 一時 YAML パス
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        # $rulePath = "$PSScriptRoot\rules\generate_rules\generated_sigmarule_${timestamp}_${idx}.yml"
        $rulePath = "$PSScriptRoot\rules\generate_rules\generated_sigmarule_test.yml"
        $rule | Out-File -Encoding utf8 $rulePath

        Write-Output "============= Sigma Rule ================="
        Write-Output ""
        Write-Output "$rule"
        Write-Output ""
        Write-Output "=========================================="
        Write-Output "Executing Sigma rule test for $outputFile`n"

        # ---- 3) 構文テスト ---------------------------------
        # $syntaxOk = & "$PSScriptRoot\syntaxTest.ps1" -RuleFilePath $rulePath
        $syntaxOk = $true
        if (-not $syntaxOk) { $idx++; continue }

        # ---- 4) 検知テスト ---------------------------------
        $detectRes = & "$PSScriptRoot\detectTest.ps1" -RulePath $rulePath `
                     -StartTime $startTime -EndTime $endTime
        $coverage  = $detectRes.Coverage
        if ($detectRes.Status -ne "OK") { $idx++; continue }

        # ---- 5) FP テスト ----------------------------------
        $fpRes = & "$PSScriptRoot\fpTest.ps1" -RulePath $rulePath
        # 必要なら最適化や再生成ロジックをここで呼ぶ

        $results += [PSCustomObject]@{
            Iteration = $iteration
            Index = $idx
            Detect = $detectRes.Hits
            FP = $fpRes.Hits
        }
        $idx++
    }
    Print-IterationSummary -Data $results
    $iteration++
}
