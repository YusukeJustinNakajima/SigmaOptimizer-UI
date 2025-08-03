# OpenAISigmaModule.psm1 - Enhanced with Claude API support

# API Provider Enum
enum AIProvider {
    OpenAI
    Claude
}

$envProvider = $env:AI_PROVIDER
if ($envProvider -eq "Claude") {
    $script:defaultProvider = [AIProvider]::Claude
} elseif ($envProvider -eq "OpenAI") {
    $script:defaultProvider = [AIProvider]::OpenAI
} else {
    $script:defaultProvider = [AIProvider]::OpenAI
}

$script:defaultModel = $env:AI_MODEL

# OpenAI API settings
$script:openaiApiUrl = "https://api.openai.com/v1/chat/completions"
$script:openaiApiKey = $env:OPENAI_APIKEY

# Claude API settings
$script:claudeApiUrl = "https://api.anthropic.com/v1/messages"
$script:claudeApiKey = $env:CLAUDE_APIKEY
$script:claudeApiVersion = "2023-06-01"

# Default provider
$script:defaultProvider = [AIProvider]::OpenAI

# Check API keys
if (-not $script:openaiApiKey -and -not $script:claudeApiKey) {
    Write-Warning "No API keys found. Please set OPENAI_APIKEY or CLAUDE_APIKEY environment variables."
}

# Load prompt files
try {

    $script:openai_llmRole = Get-Content -Path "$PSScriptRoot\prompts\prompt_for_openai.txt" -Raw -ErrorAction SilentlyContinue
    $script:claude_llmRole = Get-Content -Path "$PSScriptRoot\prompts\prompt_for_claude.txt" -Raw -ErrorAction SilentlyContinue
    
    $script:expected_output = Get-Content -Path "$PSScriptRoot\prompts\expected_outputs.txt" -Raw -ErrorAction Stop
    $script:unexpected_output = Get-Content -Path "$PSScriptRoot\prompts\unexpected_outputs.txt" -Raw -ErrorAction Stop
    
    $script:openai_llmRole = $script:openai_llmRole + $script:expected_output + $script:unexpected_output
    $script:claude_llmRole = $script:claude_llmRole + $script:expected_output + $script:unexpected_output
}
catch {
    Write-Warning "Could not load some prompt files. Using defaults where needed."
}

function Set-DefaultAIProvider {
    param (
        [AIProvider]$Provider
    )
    
    $script:defaultProvider = $Provider
    Write-Output "Default AI provider set to: $Provider"
}

function Get-DefaultAIProvider {
    return $script:defaultProvider
}

function Invoke-ClaudeRequest {
    param (
        [string]$model,
        [string]$systemContent,
        [string]$userContent,
        [double]$temperature = 0.3,
        [int]$maxTokens = 4096
    )

    if ([string]::IsNullOrWhiteSpace($systemContent) -or [string]::IsNullOrWhiteSpace($userContent)) {
        throw "One or more input parameters are null or empty."
    }

    if (-not $script:claudeApiKey) {
        throw "Claude API key not configured"
    }

    $headers = @{
        "x-api-key" = $script:claudeApiKey
        "anthropic-version" = $script:claudeApiVersion
        "content-type" = "application/json"
    }

    # Prepare the request body
    $body = @{
        model = $model
        max_tokens = $maxTokens
        temperature = $temperature
        system = $systemContent
        messages = @(
            @{
                role = "user"
                content = $userContent
            }
        )
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $response = Invoke-RestMethod -Uri $script:claudeApiUrl `
            -Headers $headers `
            -Method Post `
            -Body $body `
            -ErrorAction Stop
            
        if ($response.content -and $response.content[0].text) {
            return $response.content[0].text
        }
        else {
            throw "No content in Claude API response"
        }
    }
    catch {
        $errorMsg = "Claude API Request Error: $($_.Exception.Message)"
        if ($_.ErrorDetails) {
            $errorMsg += " Details: $($_.ErrorDetails)"
        }
        Write-Output $errorMsg
        return $null
    }
}

function Invoke-OpenAIRequest {
    param (
        [string]$model,
        [string]$roleContent,
        [string]$userContent,
        [double]$temperature = 0.3,
        [int]$maxTokens = 10000
    )

    if ([string]::IsNullOrWhiteSpace($roleContent) -or [string]::IsNullOrWhiteSpace($userContent)) {
        throw "One or more input parameters are null or empty."
    }

    if (-not $script:openaiApiKey) {
        throw "OpenAI API key not configured"
    }

    $headers = @{
        "Content-Type"  = "application/json; charset=utf-8"
        "Authorization" = "Bearer $script:openaiApiKey"
    }

    # Escape special characters in user content
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
            temperature = $temperature
            max_tokens = $maxTokens
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
        
        $response = Invoke-RestMethod -Uri $script:openaiApiUrl `
            -Headers $headers `
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
        $errorMsg = "OpenAI API Request Error: $($_.Exception.Message)"
        if ($_.ErrorDetails) {
            $errorMsg += " Details: $($_.ErrorDetails)"
        }
        Write-Output $errorMsg
        return $null
    }
}

function Invoke-AIRequest {
    param (
        [AIProvider]$Provider = $script:defaultProvider,
        [string]$model,
        [string]$systemContent,
        [string]$userContent,
        [double]$temperature = 0.3,
        [int]$maxTokens = 4096
    )

    # Model validation and defaults
    if ([string]::IsNullOrWhiteSpace($model)) {
        switch ($Provider) {
            ([AIProvider]::OpenAI) { $model = "gpt-4.1" }
            ([AIProvider]::Claude) { $model = "claude-sonnet-4-20250514" }
        }
    }

    switch ($Provider) {
        ([AIProvider]::OpenAI) {
            if (-not $script:openaiApiKey) {
                throw "OpenAI API key not configured. Please set OPENAI_APIKEY environment variable."
            }
            return Invoke-OpenAIRequest -model $model `
                -roleContent $systemContent `
                -userContent $userContent `
                -temperature $temperature `
                -maxTokens $maxTokens
        }
        ([AIProvider]::Claude) {
            if (-not $script:claudeApiKey) {
                throw "Claude API key not configured. Please set CLAUDE_APIKEY environment variable."
            }
            return Invoke-ClaudeRequest -model $model `
                -systemContent $systemContent `
                -userContent $userContent `
                -temperature $temperature `
                -maxTokens $maxTokens
        }
        default {
            throw "Unknown AI provider: $Provider"
        }
    }
}

function New-SigmaRule { 
    param ( 
        [string]$evtxLog,
        [string]$Provider = $env:AI_PROVIDER,
        [string]$model = $env:AI_MODEL
    ) 

    if ([string]::IsNullOrWhiteSpace($evtxLog)) { 
        Write-Output "Error: No valid logs found for Sigma rule generation." 
        return $null 
    } 

    $providerEnum = [AIProvider]::OpenAI
    if ($Provider -eq "Claude") {
        $providerEnum = [AIProvider]::Claude
    }

    $roleContentToUse = ""

    if ($Provider -eq "Claude") {
        $roleContentToUse = $script:claude_llmRole
    } else {
        $roleContentToUse = $script:openai_llmRole
    }

    # Fallback prompt if files not loaded
    if ([string]::IsNullOrWhiteSpace($roleContentToUse)) {
        $roleContentToUse = "You are a cybersecurity expert creating Sigma rules. Generate a complete, valid Sigma rule in YAML format."
    }

    # Set default model if not specified
    if ([string]::IsNullOrWhiteSpace($model)) {
        switch ($Provider) {
            ([AIProvider]::OpenAI) { $model = "gpt-4.1" }
            ([AIProvider]::Claude) { $model = "claude-sonnet-4-20250514" }
        }
    }

    Write-Verbose "Using $Provider with model: $model"

    # Generate Sigma rule using selected provider
    $sigmaRule = Invoke-AIRequest -Provider $Provider `
        -model $model `
        -systemContent $roleContentToUse `
        -userContent $evtxLog `
        -temperature 0.3 `
        -maxTokens 10000

    if ($sigmaRule) { 
        return $sigmaRule 
    } 
    else { 
        Write-Output "Failed to generate Sigma Rule using $Provider." 
        return $null 
    } 
}

function Test-AIConnection {
    param (
        [AIProvider]$Provider = $script:defaultProvider
    )
    
    $testPrompt = "Respond with 'OK' if you receive this message."
    
    try {
        switch ($Provider) {
            ([AIProvider]::OpenAI) {
                if (-not $script:openaiApiKey) {
                    Write-Output "OpenAI API key not configured"
                    return $false
                }
                $response = Invoke-OpenAIRequest -model "gpt-4o-mini" `
                    -roleContent "You are a test assistant." `
                    -userContent $testPrompt `
                    -maxTokens 10
            }
            ([AIProvider]::Claude) {
                if (-not $script:claudeApiKey) {
                    Write-Output "Claude API key not configured"
                    return $false
                }
                $response = Invoke-ClaudeRequest -model "claude-3-haiku-20240307" `
                    -systemContent "You are a test assistant." `
                    -userContent $testPrompt `
                    -maxTokens 10
            }
        }
        
        if ($response) {
            Write-Output "$Provider API connection successful"
            return $true
        }
        else {
            Write-Output "$Provider API connection failed"
            return $false
        }
    }
    catch {
        Write-Output "$Provider API connection error: $_"
        return $false
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Invoke-OpenAIRequest',
    'Invoke-ClaudeRequest', 
    'Invoke-AIRequest',
    'New-SigmaRule',
    'Set-DefaultAIProvider',
    'Get-DefaultAIProvider',
    'Test-AIConnection'
)