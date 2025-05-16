# SigmaRuleTests.psm1

Import-Module Pester -ErrorAction SilentlyContinue
Import-Module powershell-yaml -ErrorAction SilentlyContinue

# Function to retrieve a rule file
function Get-RuleFiles {
    [CmdletBinding()]
    param (
        [string]$RulesPath = ".\rules",
        [string]$SpecificFile
    )
    if ($SpecificFile) {
        # If $SpecificFile is not an absolute path, combine with $PSScriptRoot
        if (-not ([System.IO.Path]::IsPathRooted($SpecificFile))) {
            $SpecificFile = Join-Path $PSScriptRoot $SpecificFile
        }
        if (Test-Path $SpecificFile) {
            $files = @(Get-Item -Path $SpecificFile | Select-Object -ExpandProperty FullName)
            # Write-Output "[DEBUG] Specified file '$($SpecificFile)' found."
        }
        else {
            Write-Output "[DEBUG] Specified file '$($SpecificFile)' not found."
            $files = @()
        }
    }
    else {
        $files = Get-ChildItem -Path $RulesPath -Filter *.yml -Recurse | Select-Object -ExpandProperty FullName
    }
    # Write-Output "[DEBUG] Found $($files.Count) YAML file(s)."
    return $files
}

# Function to get the content of a specified file (UTF-8 BOM supported)
function Get-RuleContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $content = [System.Text.Encoding]::UTF8.GetString($bytes)
    return $content
}

# Function to convert YAML text to OrderedDictionary
function Get-YamlObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    $yamlText = Get-RuleContent -FilePath $FilePath
    try {
        $yamlObj = ConvertFrom-Yaml $yamlText
        $orderedYaml = [System.Collections.Specialized.OrderedDictionary]::new()
        foreach ($key in $yamlObj.Keys) {
            $orderedYaml[$key] = $yamlObj[$key]
        }
        return $orderedYaml
    }
    catch {
        Write-Output "[ERROR] Failed to parse YAML for file: $FilePath"
        return $null
    }
}

# Function to get the first key of an OrderedDictionary or hash table
function Get-FirstKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Hashtable
    )
    if ($Hashtable -is [System.Collections.Specialized.OrderedDictionary] -and $Hashtable.Count -gt 0) {
        return $Hashtable.Keys[0]
    }
    elseif ($Hashtable -and $Hashtable.Count -gt 0) {
        return ($Hashtable.Keys | Select-Object -First 1)
    }
    return $null
}

function Get-FirstKeyFromFile {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    $lines = Get-Content -Path $FilePath -Encoding utf8
    foreach ($line in $lines) {
        # Skip blank lines and comment lines (lines beginning with #)
        if ($line.Trim() -eq "" -or $line.Trim().StartsWith("#")) {
            continue
        }
        # Look for the “key:” format (be careful with spaces)
        if ($line -match '^\s*([^:\s]+)\s*:') {
            return $matches[1]
        }
    }
    return $null
}


# Function to run the Pester test
function Invoke-SigmaRuleTests {
    [CmdletBinding()]
    param (
        [string]$RulesPath = ".\rules",
        [string]$SpecificFile = ""
    )

    # If SpecificFile is a relative path, convert it to an absolute path
    if ($SpecificFile -and -not ([System.IO.Path]::IsPathRooted($SpecificFile))) {
        $SpecificFile = Join-Path $PSScriptRoot $SpecificFile
    }

    # Pester Test Script Template
    $testScriptTemplate = @"
Describe 'Sigma Rule Tests' {

    Context 'Trademark Compliance' {
        It 'should not contain forbidden trademarks' {
            `$files = Get-RuleFiles -RulesPath "$RulesPath" -SpecificFile "$SpecificFile"
            `$violatingFiles = @()
            foreach (`$file in `$files) {
                `$content = Get-RuleContent -FilePath `$file
                foreach (`$tm in @('MITRE ATT&CK', 'ATT&CK')) {
                    if (`$content -match [regex]::Escape(`$tm)) {
                        Write-Output "File $($file) contains trademark $($tm)"
                        `$violatingFiles += `$file
                        break
                    }
                }
            }
            (`$violatingFiles.Count) | Should -BeExactly 0 -Because "No rule file should contain forbidden trademark references."
        }
    }

    Context 'Title in First Line' {
        It 'should have "title" as the first key in the YAML file' {
            `$files = Get-RuleFiles -RulesPath "$RulesPath" -SpecificFile "$SpecificFile"
            `$faultyFiles = @()
            foreach (`$file in `$files) {
                `$firstKey = Get-FirstKeyFromFile -FilePath `$file
                if (`$firstKey -ne "title") {
                    Write-Output "File $($file): first key is '$($firstKey)' (expected 'title')."
                    `$faultyFiles += `$file
                }
            }
            (`$faultyFiles.Count) | Should -BeExactly 0 -Because "Every rule file should have 'title' as the first key."
        }
    }


    Context 'Optional License Field' {
        It 'should have license as a string if present' {
            `$files = Get-RuleFiles -RulesPath "$RulesPath" -SpecificFile "$SpecificFile"
            `$faultyFiles = @()
            foreach (`$file in `$files) {
                `$yamlObj = Get-YamlObject -FilePath `$file
                if (`$yamlObj -is [hashtable] -and `$yamlObj.ContainsKey("license")) {
                    if (-not (`$yamlObj.license -is [string])) {
                        Write-Output "File $($file) has a malformed license field."
                        `$faultyFiles += `$file
                    }
                }
            }
            (`$faultyFiles.Count) | Should -BeExactly 0 -Because "License field must be a string if present."
        }
    }

    Context 'Duplicate Detections' {
        It 'should not have duplicate detection logic among rule files' {
            `$files = Get-RuleFiles -RulesPath "$RulesPath" -SpecificFile "$SpecificFile"
            `$detections = @{}
            `$duplicateFiles = @()
            foreach (`$file in `$files) {
                `$yamlObj = Get-YamlObject -FilePath `$file
                if (`$yamlObj -is [hashtable] -and `$yamlObj.ContainsKey("detection")) {
                    `$detJson = `$yamlObj.detection | ConvertTo-Json -Depth 10
                    foreach (`$key in `$detections.Keys) {
                        if (`$detections[`$key] -eq `$detJson) {
                            Write-Output "Duplicate detection logic found in $($file) and $($key)"
                            `$duplicateFiles += `$file
                            break
                        }
                    }
                    if (-not (`$duplicateFiles -contains `$file)) {
                        `$detections[`$file] = `$detJson
                    }
                }
            }
            (`$duplicateFiles.Count) | Should -BeExactly 0 -Because "There should be no duplicate detection logic among rule files."
        }
    }

    Context "File Name Tests" {
        It "should have valid file names and logsource fields" {
            `$faultyRules = @()
            `$nameHash = @{}
            `$filenamePattern = '^[a-z0-9_]{10,90}\.yml$'
            `$files = Get-RuleFiles -RulesPath "$RulesPath" -SpecificFile "$SpecificFile"
            foreach (`$file in `$files) {
                `$filename = [System.IO.Path]::GetFileName(`$file)
                `$yamlObj = Get-YamlObject -FilePath `$file

                # Duplicate filename checking
                if (`$nameHash.ContainsKey(`$filename)) {
                    Write-Output "File $($file) is a duplicate file name."
                    `$faultyRules += `$file
                }
                else {
                    `$nameHash[`$filename] = `$true
                }

                # Extension check
                if (-not `$filename.EndsWith(".yml")) {
                    Write-Output "File $($file) has an invalid extension (expected .yml)."
                    `$faultyRules += `$file
                }

                # File name length check
                `$len = `$filename.Length
                if (`$len -gt 90) {
                    Write-Output "File $($file) has a file name too long (>90 characters)."
                    `$faultyRules += `$file
                }
                elseif (`$len -lt 14) {
                    Write-Output "File $($file) has a file name too short (<14 characters)."
                    `$faultyRules += `$file
                }

                # Regular expressions and checking for the inclusion of underscores
                if (`$filename -notmatch `$filenamePattern -or `$filename -notmatch "_") {
                    Write-Output "File $($file) has a file name that doesn't match our standard."
                    `$faultyRules += `$file
                }

                # logsource validation
                `$logsource = `$yamlObj.logsource
                if (`$logsource) {
                    `$validProducts = @("windows", "macos", "linux", "aws", "azure", "gcp", "m365", "okta", "onelogin", "github", "django")
                    `$validCategories = @("process_creation", "image_load", "file_event", "registry_set", "registry_add", "registry_event",
                                        "registry_delete", "registry_rename", "process_access", "driver_load", "dns_query",
                                        "ps_script", "ps_module", "ps_classic_start", "pipe_created", "network_connection",
                                        "file_rename", "file_delete", "file_change", "file_access", "create_stream_hash",
                                        "create_remote_thread", "dns", "firewall", "webserver")
                    `$validServices = @("auditd", "modsecurity", "diagnosis-scripted", "firewall-as", "msexchange-management",
                                    "security", "system", "taskscheduler", "terminalservices-localsessionmanager", "windefend",
                                    "wmi", "codeintegrity-operational", "bits-client", "applocker", "dns-server-analytic",
                                    "bitlocker", "capi2", "certificateservicesclient-lifecycle-system", "pim")
                    foreach (`$key in `$logsource.Keys) {
                        `$value = `$logsource[`$key]
                        if (`$key -eq "definition") { continue }
                        if (`$key -eq "product") {
                            if (`$validProducts -notcontains `$value) {
                                Write-Output "[ERROR] Invalid product '$($value)' found in logsource in file $($file)!"
                                `$faultyRules += `$file
                                continue
                            }
                        }
                        if (`$key -eq "category") {
                            if (`$validCategories -notcontains `$value) {
                                Write-Output "[ERROR] Invalid category '$($value)' found in logsource in file $($file)!"
                                `$faultyRules += `$file
                                continue
                            }
                        }
                        if (`$key -eq "service") {
                            if (`$validServices -notcontains `$value) {
                                Write-Output "[ERROR] Invalid service '$($value)' found in logsource in file $($file)!"
                                `$faultyRules += `$file
                                continue
                            }
                        }
                    }
                }
                else {
                    Write-Output "File $($file) does not contain a logsource field."
                    `$faultyRules += `$file
                }
            }
            (`$faultyRules.Count) | Should -BeExactly 0 -Because "All rule file names and logsource fields must meet the naming conventions."
        }
    }
}
"@

    # Write test script to temporary file and run Invoke-Pester
    $tempTestFile = Join-Path $env:TEMP "TempSigmaTests.ps1"
    $testScriptTemplate | Out-File -FilePath $tempTestFile -Encoding utf8   
    
    $testResult = Invoke-Pester -Script $tempTestFile -PassThru -Quiet

    # Temporary file deletion (wait a bit if in use)
    Start-Sleep -Seconds 0.5
    Remove-Item $tempTestFile -Force

    $FailedCount = $testResult.FailedCount
    
    if ($FailedCount -eq 0) {
        Write-Host -ForegroundColor Green "All tests passed successfully!"
        return $true
    } else {
        Write-Host -ForegroundColor Red "$FailedCount tests failed!"
        return $false
    }
    
}

Export-ModuleMember -Function Invoke-SigmaRuleTests
