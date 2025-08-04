# llm-optimize.ps1
param(
    [Parameter(Mandatory=$true)]
    [string]$RulePath,
    
    [Parameter(Mandatory=$true)]
    [string]$OptimizationPrompt,
    
    [Parameter(Mandatory=$true)]
    [string]$CurrentRule,
    
    [Parameter(Mandatory=$false)]
    [string]$Provider = $env:AI_PROVIDER,
    
    [Parameter(Mandatory=$false)]
    [string]$Model = $env:AI_MODEL
)

if ([string]::IsNullOrWhiteSpace($Provider)) {
    $Provider = "OpenAI"
}

if ([string]::IsNullOrWhiteSpace($Model)) {
    switch ($Provider) {
        "OpenAI" { $Model = "gpt-4.1" }
        "Claude" { $Model = "claude-sonnet-4-20250514" }
        default { $Model = "gpt-4.1" }
    }
}

# Import LLM module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\LLM_SigmaModule.psm1" -Force

# Load expected output format
try {
    $expectedOutputPath = Join-Path $scriptPath "prompts\expected_outputs_for_optimize.txt"
    $script:expected_outputs_for_optimize = Get-Content -Path $expectedOutputPath -Raw -ErrorAction Stop
    Write-Host "Loaded expected output format" -ForegroundColor Green
}
catch {
    Write-Warning "Could not load expected_outputs.txt: $_"
    $script:expected_outputs_for_optimize = ""
}

# Check if API key is available based on provider
if ($Provider -eq "Claude") {
    if (-not $env:CLAUDE_APIKEY) {
        Write-Error "CLAUDE_APIKEY environment variable is not set"
        $output = @{
            Success = $false
            Error = "Claude API key not configured"
            Message = "Please set CLAUDE_APIKEY environment variable"
        }
        $output | ConvertTo-Json -Depth 10
        exit 1
    }
} else {
    if (-not $env:OPENAI_APIKEY) {
        Write-Error "OPENAI_APIKEY environment variable is not set"
        $output = @{
            Success = $false
            Error = "OpenAI API key not configured"
            Message = "Please set OPENAI_APIKEY environment variable"
        }
        $output | ConvertTo-Json -Depth 10
        exit 1
    }
}

# Function to optimize Sigma rule with LLM
function Optimize-SigmaRule {
    param(
        [string]$Rule,
        [string]$Prompt,
        [string]$ProviderName = "OpenAI",
        [string]$ModelName = "gpt-4.1"
    )
    
    # Create the role content for optimization
    $roleContent = @"
You are a cybersecurity expert specializing in Sigma rule optimization and threat hunting.
Your task is to optimize the **Current Sigma Rule** based on specific requirements while maintaining its effectiveness.

---

**CRITICAL INSTRUCTIONS:**

* Output the **entire Sigma rule** in YAML format every time (not just the modified sections).
* Do NOT use markdown code blocks or provide any explanations

---

**SIGMA RULE STRUCTURE:**

**You may modify ONLY the following fields:**

* **title**: Descriptive and concise rule title
* **detection**: Optimize detection logic and include specific exclusions to reduce false positives
* **falsepositives**: Explicitly list potential false positives

**You MUST NOT modify the following fields:**

* id
* status
* description
* author
* date
* tags
* logsource
* level

---

**OPTIMIZATION GUIDELINES:**

* Edit ONLY the allowed fields listed above
* Strengthen detection logic while preserving accuracy
* Use proper and valid Sigma syntax

---

**OPTIMIZATION TIPS:**

1. **Temporarily Remove 'filter' Blocks:**
   For broader threat hunting, consider removing or commenting out existing filter (negation) conditions to observe a wider set of relevant and noisy events. This helps identify overlooked patterns, though more false positives will appear.

2. **Loosen Selection Criteria with Wildcards/Regex:**
   For example, change strict conditions such as Image|endswith: '\\wsmprovhost.exe' to more flexible ones like Image|contains: 'wsmprovhost' to capture binaries with similar names in unusual paths.

3. **Leverage False Positives for Detection:**
   Intentionally include scenarios known to cause false positives (as described in the falsepositives field) within your detection logic to hunt for suspicious cases that are normally excluded. This can reveal abnormal behavior hidden among legitimate activity.

$script:expected_outputs_for_optimize
"@

    # Create the user content with clearer instructions
    $userContent = @"
Current Sigma Rule:
$Rule

**Optimization Request**: $Prompt

IMPORTANT: Return ONLY the optimized Sigma rule in plain YAML format. Do not include any markdown formatting, code blocks, or explanations.
"@

    try {
        # Call LLM API using string provider name directly
        Write-Host "Calling $ProviderName API with model: $ModelName" -ForegroundColor Yellow

        # Use New-SigmaRule function which accepts string parameters
        $optimizedRule = New-SigmaRule `
            -evtxLog $userContent `
            -Provider $ProviderName `
            -model $ModelName
        
        Write-Host "$ProviderName API call completed" -ForegroundColor Green
        
        if (-not $optimizedRule) {
            throw "Failed to get response from $ProviderName API"
        }
        
        # Extract YAML content if wrapped in code blocks
        if ($optimizedRule -match '```(?:yaml|yml)?\s*\n([\s\S]*?)\n```') {
            $optimizedRule = $matches[1]
        }
        
        # Clean up the response - remove any duplicate fields
        $lines = $optimizedRule -split "`n"
        $cleanedLines = @()
        $seenFields = @{}
        $inFieldsList = $false
        $fieldsList = @()
        
        foreach ($line in $lines) {
            if ($line -match '^\s*fields:\s*$') {
                $inFieldsList = $true
                $cleanedLines += $line
            }
            elseif ($inFieldsList -and $line -match '^\s*-\s*(.+)$') {
                $field = $matches[1].Trim()
                if (-not $seenFields.ContainsKey($field) -and $fieldsList.Count -lt 15) {
                    $seenFields[$field] = $true
                    $fieldsList += $field
                    $cleanedLines += $line
                }
            }
            elseif ($line -match '^[a-z]+:' -and -not $inFieldsList) {
                $inFieldsList = $false
                $cleanedLines += $line
            }
            else {
                $cleanedLines += $line
            }
        }
        
        $optimizedRule = $cleanedLines -join "`n"
        
        return $optimizedRule.Trim()
    }
    catch {
        Write-Error "Error optimizing rule: $_"
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $null
    }
}

# Function to validate the optimized rule structure
function Test-SigmaRuleStructure {
    param(
        [string]$Rule
    )
    
    try {
        # Basic validation - check for required fields
        $requiredFields = @('title', 'detection')
        $missingFields = @()
        
        foreach ($field in $requiredFields) {
            if ($Rule -notmatch "^$field\s*:", 'Multiline') {
                $missingFields += $field
            }
        }
        
        if ($missingFields.Count -gt 0) {
            Write-Warning "Optimized rule missing required fields: $($missingFields -join ', ')"
            return $false
        }
        
        # Check for basic YAML syntax
        if ($Rule -notmatch '^(title|id|status|description|references|author|date|modified|tags|logsource|detection|falsepositives|level|rule):', 'Multiline') {
            Write-Warning "Optimized rule does not appear to be a valid Sigma rule"
            return $false
        }
        
        return $true
    }
    catch {
        Write-Error "Error validating rule structure: $_"
        return $false
    }
}

# Main execution
try {
    Write-Host "Starting Sigma rule optimization..." -ForegroundColor Green
    Write-Host "Using Provider: $Provider with Model: $Model" -ForegroundColor Cyan
    
    # Optimize the rule
    $optimizedRule = Optimize-SigmaRule `
        -Rule $CurrentRule `
        -Prompt $OptimizationPrompt `
        -ProviderName $Provider `
        -ModelName $Model
    
    if (-not $optimizedRule) {
        throw "Failed to optimize rule"
    }
    
    # Validate the optimized rule
    $isValid = Test-SigmaRuleStructure -Rule $optimizedRule
    
    if (-not $isValid) {
        Write-Warning "Optimized rule may have structural issues, but continuing..."
    }
    
    # Save the optimized rule to a temporary file
    $tempPath = [System.IO.Path]::GetTempFileName()
    $optimizedRule | Out-File -FilePath $tempPath -Encoding UTF8 -NoNewline
    
    # Prepare output
    $output = @{
        Success = $true
        OptimizedRule = $optimizedRule
        RulePath = $RulePath
        TempPath = $tempPath
        Message = "Rule optimized successfully using $Provider ($Model)"
        Provider = $Provider
        Model = $Model
    }
    
    # Output as JSON
    $output | ConvertTo-Json -Depth 10
}
catch {
    $errorOutput = @{
        Success = $false
        Error = $_.Exception.Message
        OptimizedRule = $null
        Message = "Failed to optimize rule: $($_.Exception.Message)"
        Provider = $Provider
        Model = $Model
    }
    
    $errorOutput | ConvertTo-Json -Depth 10
    exit 1
}