# helpers/Common.ps1
param(
    [switch]$NoModule     # 単体テスト用
)

if (-not $NoModule) {
    Import-Module "$PSScriptRoot\..\OpenAI_SigmaModule.psm1" -Force
    Import-Module "$PSScriptRoot\..\SigmaRuleTests.psm1"    -Force
    Import-Module Invoke-ArgFuscator
}

function Insert-MissingTags {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$RuleBlock,
        [Parameter(Mandatory=$true)]
        [bool]$HasAuthor,
        [Parameter(Mandatory=$true)]
        [bool]$HasDate
    )

    $newBlock = @()
    $foundId = $false
    foreach ($line in $RuleBlock) {
        if ($line -match "^\s*id:") {
            if (-not $foundId) {
                $foundId = $true
                $newBlock += "id: $(New-Guid)"
            }
        }
        else {
            $newBlock += $line
        }
    }
    
    if (-not $foundId) {
        $tempBlock = @()
        $inserted = $false
        foreach ($line in $newBlock) {
            $tempBlock += $line
            if (-not $inserted -and $line -match "^\s*title:") {
                $tempBlock += "id: $(New-Guid)"
                $inserted = $true
            }
        }
        $newBlock = $tempBlock
    }
    
    $levelIndex = -1
    for ($i = 0; $i -lt $newBlock.Count; $i++) {
        if ($newBlock[$i] -match "^\s*level:") {
            $levelIndex = $i
            break
        }
    }
    if ($levelIndex -eq -1) { $levelIndex = $newBlock.Count }
    
    $insertLines = @()
    if (-not $HasAuthor) {
        $insertLines += "author: Yusuke Nakajima"
    }
    if (-not $HasDate) {
        $insertLines += "date: $(Get-Date -Format 'yyyy-MM-dd')"
    }
    
    if ($insertLines.Count -gt 0) {
        $before = $newBlock[0..($levelIndex - 1)]
        $after = $newBlock[$levelIndex..($newBlock.Count - 1)]
        $newBlock = $before + $insertLines + $after
    }
    
    return $newBlock
}

function Extract-SigmaRules {
    param(
        [Parameter(Mandatory=$true)]
        [AllowNull()][object]$SigmaOutput
    )

    if ($SigmaOutput -isnot [string]) {
        $SigmaOutput = ($SigmaOutput | Out-String)
    }

    $rules = @()         
    $currentRule = @()   
    $extracting = $false 
    
    $hasAuthor = $false
    $hasDate   = $false
    
    foreach ($line in $SigmaOutput -split "`n") {
        
        if ($line -match "^\s*author:") {
            $line = "author: [your_name_here]"
            $hasAuthor = $true
        }
        
        if ($line -match "^\s*date:") {
            $line = "date: $(Get-Date -Format 'yyyy-MM-dd')"
            $hasDate = $true
        }
        
        if ($line -match "^\s*title:") {
            
            if ($extracting -eq $true -and $currentRule.Count -gt 0) {
                $currentRule = Insert-MissingTags -RuleBlock $currentRule -HasAuthor $hasAuthor -HasDate $hasDate
                $rules += ($currentRule -join "`n")
                $currentRule = @()
            }
            $extracting = $true

            $hasAuthor = $false
            $hasDate = $false
        }
        
        if ($extracting) {
            $currentRule += $line
        }
        
        if ($line -match "^\s*level:") {
            if ($extracting) {
                $currentRule = Insert-MissingTags -RuleBlock $currentRule -HasAuthor $hasAuthor -HasDate $hasDate
                $rules += ($currentRule -join "`n")
                $currentRule = @()
                $extracting = $false
            }
        }
    }
    
    if ($currentRule.Count -gt 0) {
        $currentRule = Insert-MissingTags -RuleBlock $currentRule -HasAuthor $hasAuthor -HasDate $hasDate
        $rules += ($currentRule -join "`n")
    }
    
    return $rules
}

function Generate-CandidateSummary {
    param(
        [Parameter(Mandatory=$true)]
        [array]$CandidateResults
    )
    
    $summaryText = ""
    foreach ($candidate in $CandidateResults) {
        $summaryText += "#### Candidate $($candidate.CandidateIndex) ####`n`n"
        $summaryText += "##### Rule #####`n"
        $summaryText += "$($candidate.RuleText)`n`n"
        $summaryText += "##### Coverage #####`n"
        $summaryText += "$($candidate.Coverage)`n`n"
        $summaryText += "##### Detectable Events #####`n"
        $summaryText += "$($candidate.DetectionResult)`n`n"
    }
    return $summaryText
}

function Print-FormattedTable {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Data
    )
    if ($Data.Count -eq 0) {
        Write-Host "No data to display."
        return
    }
    
    $properties = $Data[0].psobject.Properties.Name
    $widths = @{}

    foreach ($prop in $properties) {
        $maxWidth = $prop.Length
        foreach ($row in $Data) {
            $valueStr = $row.$prop.ToString()
            if ($valueStr.Length -gt $maxWidth) {
                $maxWidth = $valueStr.Length
            }
        }
        $widths[$prop] = $maxWidth
    }

    $headerLine = "|"
    $separatorLine = "+"
    foreach ($prop in $properties) {
        $headerLine += " " + $prop.PadRight($widths[$prop]) + " |"
        $separatorLine += "-" * ($widths[$prop] + 2) + "+"
    }

    Write-Host $separatorLine -ForegroundColor Cyan
    Write-Host $headerLine -ForegroundColor Cyan
    Write-Host $separatorLine -ForegroundColor Cyan

    foreach ($row in $Data) {
        $line = "|"
        foreach ($prop in $properties) {
            $valueStr = $row.$prop.ToString()
            if ($valueStr -match '^\d+%?$') {
                $line += " " + $valueStr.PadLeft($widths[$prop]) + " |"
            }
            else {
                $line += " " + $valueStr.PadRight($widths[$prop]) + " |"
            }
        }
        Write-Host $line
    }

    Write-Host $separatorLine -ForegroundColor Cyan
}

function Print-IterationSummary {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Data
    )

    $groupedResults = $Data | Group-Object -Property Iteration | Sort-Object Name

    foreach ($group in $groupedResults) {
        Write-Host "===== Iteration $($group.Name) Summary =====" -ForegroundColor Cyan
        $candidates = $group.Group | Select-Object CandidateIndex, DetectionResult, FpCount
        Print-FormattedTable -Data $candidates
        Write-Host ""
    }
}
