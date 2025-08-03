# OpenAISigmaModule.psm1

# OpenAI API settings
$script:apiUrl = "https://api.openai.com/v1/chat/completions"
$script:apiKey = $env:OPENAI_APIKEY

if (-not $script:apiKey) {
    Write-Error "OpenAI API key not found. Please set OPENAI_APIKEY environment variable."
}

$script:headers = @{
    "Content-Type"  = "application/json; charset=utf-8"
    "Authorization" = "Bearer $script:apiKey"
}

try {
    $script:llmRole_iteration_first = Get-Content -Path "$PSScriptRoot\prompts\prompt_for_first_generation.txt" -Raw -ErrorAction Stop
    $script:llmRole_iteration_after_second = Get-Content -Path "$PSScriptRoot\prompts\prompt_for_after_second_generation.txt" -Raw -ErrorAction Stop
    $script:expected_output = Get-Content -Path "$PSScriptRoot\prompts\expected_outputs.txt" -Raw -ErrorAction Stop
    $script:unexpected_output = Get-Content -Path "$PSScriptRoot\prompts\unexpected_outputs.txt" -Raw -ErrorAction Stop
    
    $script:llmRole_iteration_first = $script:llmRole_iteration_first + $script:expected_output + $script:unexpected_output
    $script:llmRole_iteration_after_second = $script:llmRole_iteration_after_second + $script:expected_output + $script:unexpected_output
}
catch {
    Write-Warning "Could not load some prompt files. Using defaults where needed."
}

function Invoke-OpenAIRequest {
    param (
        [string]$model,
        [string]$roleContent,
        [string]$userContent
    )

    if ([string]::IsNullOrWhiteSpace($roleContent) -or [string]::IsNullOrWhiteSpace($userContent)) {
        throw "One or more input parameters are null or empty."
    }

    if (-not $script:apiKey) {
        throw "OpenAI API key not configured"
    }

    $userContent = $userContent -replace '\\', '\\'
    $userContent = $userContent -replace '"', '\"'
    $userContent = $userContent -replace "`n", '\n'
    $userContent = $userContent -replace "`r", '\r'
    $userContent = $userContent -replace "`t", '\t'

    if ($model -eq "gpt-4o" -or $model -eq "gpt-4.1") {
        $body = @{
            model = $model
            messages = @(
                @{ role = "system"; content = $roleContent }
                @{ role = "user"; content = $userContent }
            )
            temperature = 0.3
            max_tokens = 10000
        } | ConvertTo-Json -Depth 10 -Compress
    } 
    elseif ($model -eq "o1-mini") {
        $combinedContent = "$roleContent`n`n"
        $combinedContent += "$userContent`n`n"
        $body = @{
            model = $model
            messages = @(
                @{ role = "user"; content = $combinedContent }
            )
        } | ConvertTo-Json -Depth 10 -Compress
    } 
    elseif ($model -eq "o3-mini") {
        $combinedContent = "$roleContent`n`n"
        $combinedContent += "$userContent`n`n"
        $body = @{
            model = $model
            messages = @(
                @{ role = "developer"; content = $combinedContent }
            )
            reasoning_effort = "high"
        } | ConvertTo-Json -Depth 10 -Compress
    }
    
    try {
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        
        $response = Invoke-RestMethod -Uri $script:apiUrl `
            -Headers $script:headers `
            -Method Post `
            -Body $bodyBytes `
            -ErrorAction Stop
            
        if ($response.choices -and $response.choices[0].message.content) {
            return $response.choices[0].message.content
        }
        else {
            throw "No content in API response"
        }
    }
    catch {
        $errorMsg = "API Request Error: $($_.Exception.Message)"
        if ($_.ErrorDetails) {
            $errorMsg += " Details: $($_.ErrorDetails)"
        }
        Write-Output $errorMsg
        return $null
    }
}

function New-SigmaRule { 
    param ( 
        [string]$evtxLog,
        [int]$Iteration = 1
    ) 

    if ([string]::IsNullOrWhiteSpace($evtxLog)) { 
        Write-Output "Error: No valid logs found for Sigma rule generation." 
        return $null 
    } 

    if ($Iteration -gt 1) {
        $roleContentToUse = $script:llmRole_iteration_after_second
    }
    else {
        $roleContentToUse = $script:llmRole_iteration_first
    }

    if ([string]::IsNullOrWhiteSpace($roleContentToUse)) {
        $roleContentToUse = "You are a cybersecurity expert creating Sigma rules. Generate a complete, valid Sigma rule in YAML format."
    }

    $sigmaRule = Invoke-OpenAIRequest -model "gpt-4.1" -roleContent $roleContentToUse -userContent $evtxLog

    if ($sigmaRule) { 
        return $sigmaRule 
    } 
    else { 
        Write-Output "Failed to generate Sigma Rule." 
        return $null 
    } 
}

Export-ModuleMember -Function Invoke-OpenAIRequest, New-SigmaRule