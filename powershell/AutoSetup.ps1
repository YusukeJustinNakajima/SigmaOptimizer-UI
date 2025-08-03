# setup_with_baseline.ps1
# SigmaOptimizer Setup Script with Baseline Log Collection

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   SigmaOptimizer Setup & Baseline Collection   " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ====== Configuration Section ======
# Set OpenAI API Key as an environment variable (modify if needed)
$apiKeyInput = Read-Host "Enter your OpenAI API Key (or press Enter to skip if already set)"
if ($apiKeyInput) {
    $env:OPENAI_APIKEY = $apiKeyInput
    [System.Environment]::SetEnvironmentVariable('OPENAI_APIKEY', $apiKeyInput, 'User')
    Write-Host "OpenAI API Key has been set." -ForegroundColor Green
} else {
    if ($env:OPENAI_APIKEY) {
        Write-Host "Using existing OpenAI API Key." -ForegroundColor Yellow
    } else {
        Write-Warning "No OpenAI API Key found. Please set it manually later."
    }
}

Write-Host ""
Write-Host "====== Installing Required Modules ======" -ForegroundColor Yellow

# Required PowerShell modules
$requiredModules = @("Pester", "powershell-yaml", "Invoke-ArgFuscator")

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module" -ForegroundColor Cyan
        if ($module -eq "Pester") {
            Install-Module -Name "Pester" -RequiredVersion "5.7.1" -Force -AllowClobber -SkipPublisherCheck
        } else {
            Install-Module -Name $module -Force -SkipPublisherCheck
        }
    } else {
        Write-Host "Module already installed: $module" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "====== Downloading Hayabusa ======" -ForegroundColor Yellow

# GitHub repository information
$repo = "Yamato-Security/hayabusa"
$apiUrl = "https://api.github.com/repos/$repo/releases/latest"
$zipFile = "hayabusa-latest.zip"
$extractPath = "hayabusa-latest"
<#
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Headers @{"Accept"="application/vnd.github.v3+json"}
    
    # Retrieve the download URL for the latest ZIP file
    $downloadUrl = $response.assets | Where-Object { $_.name -match "win-x64.zip" } | Select-Object -ExpandProperty browser_download_url
    
    if ($downloadUrl) {
        Write-Host "Downloading Hayabusa from: $downloadUrl" -ForegroundColor Cyan
        
        # Download ZIP file
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile
        
        # Remove existing folder (cleanup)
        if (Test-Path $extractPath) {
            Remove-Item -Recurse -Force $extractPath
        }
        
        # Extract ZIP
        Expand-Archive -Path $zipFile -DestinationPath $extractPath -Force
        
        # Find the `.exe` file
        $exeFile = Get-ChildItem -Path $extractPath -Filter "*.exe" -File -Recurse | Select-Object -First 1
        
        if ($exeFile) {
            # Copy to the current directory as "hayabusa.exe"
            $destinationPath = ".\hayabusa.exe"
            Copy-Item -Path $exeFile.FullName -Destination $destinationPath -Force
            Write-Host "Hayabusa installed: $destinationPath" -ForegroundColor Green
        } else {
            Write-Warning "No .exe files found in the extracted folder."
        }
        
        # Cleanup (delete ZIP file)
        Remove-Item $zipFile -Force
        Remove-Item $extractPath -Recurse -Force
    } else {
        Write-Warning "Hayabusa download URL not found."
    }
} catch {
    Write-Error "Failed to download Hayabusa: $_"
}
#>
Write-Host ""
Write-Host "====== Extracting Benign EVTX Logs ======" -ForegroundColor Yellow

# Tar file to extract
$tarFile = "benign_evtx_logs/win10-client.tgz"
$tarExtractPath = "benign_evtx_logs/"

if (Test-Path $tarFile) {
    Write-Host "Extracting $tarFile to $tarExtractPath" -ForegroundColor Cyan
    
    # Extract using tar
    tar -xzf $tarFile -C $tarExtractPath 2>$null
    
    Write-Host "Extraction completed." -ForegroundColor Green
} else {
    Write-Warning "Tar file $tarFile not found. Skipping benign logs extraction."
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "   BASELINE LOG COLLECTION FOR FALSE POSITIVES " -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "We will now collect baseline logs from your system." -ForegroundColor Cyan
Write-Host ""
Write-Host "PURPOSE:" -ForegroundColor Yellow
Write-Host "By providing normal system logs to the LLM during rule creation," -ForegroundColor White
Write-Host "it can better distinguish between legitimate and malicious activities." -ForegroundColor White
Write-Host "This helps the LLM ignore normal behaviors and focus exclusively on" -ForegroundColor White
Write-Host "detecting actual threats, significantly reducing false positives." -ForegroundColor White
Write-Host ""
Write-Host "IMPORTANT: Please do the following:" -ForegroundColor Red
Write-Host "1. Keep this window open" -ForegroundColor White
Write-Host "2. DO NOT perform any actions on your computer" -ForegroundColor White
Write-Host "3. Let the system idle for 180 seconds (3 minutes)" -ForegroundColor White
Write-Host "4. This captures normal background activity" -ForegroundColor White
Write-Host ""

$collectBaseline = Read-Host "Ready to start baseline collection? (y/n)"

if ($collectBaseline -eq 'y' -or $collectBaseline -eq 'yes') {
    Write-Host ""
    Write-Host "Starting baseline collection..." -ForegroundColor Green
    Write-Host "Please DO NOT use your computer for the next 180 seconds (3 minutes)." -ForegroundColor Yellow
    
    # Countdown display
    for ($i = 5; $i -gt 0; $i--) {
        Write-Host "Starting in $i seconds..." -ForegroundColor Cyan
        Start-Sleep -Seconds 1
    }
    
    Write-Host ""
    Write-Host "====== COLLECTING BASELINE - DO NOT USE COMPUTER ======" -ForegroundColor Red
    
    # Record start time
    $baselineStartTime = Get-Date
    $baselineStartTimeStr = $baselineStartTime.ToString("yyyy-MM-dd HH:mm:ss")
    
    # Progress bar for 180 seconds
    $totalSeconds = 180
    for ($i = 0; $i -lt $totalSeconds; $i++) {
        $percentComplete = [int](($i / $totalSeconds) * 100)
        $remainingSeconds = $totalSeconds - $i
        $remainingMinutes = [Math]::Floor($remainingSeconds / 60)
        $remainingSecondsInMinute = $remainingSeconds % 60
        $statusText = if ($remainingMinutes -gt 0) {
            "$remainingMinutes min $remainingSecondsInMinute sec remaining"
        } else {
            "$remainingSeconds seconds remaining"
        }
        Write-Progress -Activity "Collecting baseline logs" -Status $statusText -PercentComplete $percentComplete
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity "Collecting baseline logs" -Completed
    
    # Record end time
    $baselineEndTime = Get-Date
    $baselineEndTimeStr = $baselineEndTime.ToString("yyyy-MM-dd HH:mm:ss")
    
    Write-Host ""
    Write-Host "Baseline collection period completed!" -ForegroundColor Green
    Write-Host "Processing collected logs..." -ForegroundColor Cyan
    
    # Call modified logCollector to collect baseline logs
    $scriptPath = $PSScriptRoot
    $logCollectorPath = Join-Path $scriptPath "logCollectorBaseline.ps1"
    
    # Ensure the directory exists
    if (-not (Test-Path $scriptPath)) {
        New-Item -ItemType Directory -Path $scriptPath -Force | Out-Null
    }
    
    # Create baseline collection script
    $baselineScript = @"
# logCollectorBaseline.ps1
param(
    [string]`$StartTime,
    [string]`$EndTime
)

`$scriptPath = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$cfgDir = Join-Path `$scriptPath 'config'
`$detectionPath = Join-Path `$cfgDir 'detection_fields.txt'

if (-not (Test-Path `$detectionPath)) {
    Write-Error "detection_fields.txt not found"
    exit 1
}
`$detectionFields = Get-Content `$detectionPath

`$logSources = @(
    @{Name='Microsoft-Windows-Sysmon/Operational'; MaxEvents=30}
)

Write-Host "Starting baseline log collection..." -ForegroundColor Cyan
Write-Host "Time range: `$StartTime to `$EndTime" -ForegroundColor Gray

`$allCollectedLogs = @{}
`$globalEventSignatures = @{}

foreach (`$logSource in `$logSources) {
    `$logName = `$logSource.Name
    `$maxEvents = `$logSource.MaxEvents
    
    Write-Host "`nProcessing: `$logName" -ForegroundColor Yellow
    
    try {
        `$logInfo = Get-WinEvent -ListLog `$logName -ErrorAction Stop
        Write-Host "  Log available. Total records: `$(`$logInfo.RecordCount)" -ForegroundColor Green
    } catch {
        Write-Host "  Log not available: `$_" -ForegroundColor Red
        continue
    }
    
    try {
        `$events = Get-WinEvent -FilterHashtable @{
            LogName   = `$logName
            StartTime = `$StartTime
            EndTime   = `$EndTime
        } -ErrorAction Stop | Select-Object -First 100
        
        if (-not `$events -or `$events.Count -eq 0) {
            Write-Host "  No events found in time range" -ForegroundColor Yellow
            continue
        }
        
        Write-Host "  Found `$(`$events.Count) raw events" -ForegroundColor Cyan
        
        `$uniqueLogs = @{}
        `$eventTypeCount = @{}
        
        foreach (`$event in `$events) {
            if (`$uniqueLogs.Count -ge `$maxEvents) {
                break
            }
            
            `$xml = `$event.ToXml()
            `$xmlDoc = [xml]`$xml
            
            `$eventId = `$event.Id
            `$signatureContent = ""

            if (`$xmlDoc.Event.EventData.Data) {
                `$keyFields = @()
                foreach (`$dataNode in `$xmlDoc.Event.EventData.Data) {
                    if (`$dataNode.Name -and `$dataNode.'#text') {
                        `$fieldName = `$dataNode.Name
                        `$fieldValue = `$dataNode.'#text'
                        
                        if (`$fieldName -in @('Image', 'TargetImage', 'SourceImage', 'CommandLine', 'TargetFilename', 'DestinationHostname', 'User', 'Description')) {
                            if (`$fieldValue.Length -gt 50) {
                                `$fieldValue = `$fieldValue.Substring(0, 50)
                            }
                            `$keyFields += "`${fieldName}:`${fieldValue}"
                        }
                    }
                }
                
                `$signatureContent = (`$keyFields -join '|')
                if (`$signatureContent.Length -gt 100) {
                    `$signatureContent = `$signatureContent.Substring(0, 100)
                }
            }
            
            `$signatureKey = "`${eventId}|`${signatureContent}"
            
            if (`$globalEventSignatures.ContainsKey(`$signatureKey)) {
                continue
            }
            

            if (-not `$eventTypeCount.ContainsKey(`$eventId)) {
                `$eventTypeCount[`$eventId] = 0
            }
            
            `$globalEventSignatures[`$signatureKey] = `$true
            `$eventTypeCount[`$eventId]++
            `$uniqueLogs[`$signatureKey] = `$xml
        }
        
        Write-Host "  Collected `$(`$uniqueLogs.Count) unique events" -ForegroundColor Green
        
        `$distribution = `$eventTypeCount.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5
        if (`$distribution) {
            Write-Host "  Event distribution:" -ForegroundColor Gray
            foreach (`$item in `$distribution) {
                Write-Host "    EventID `$(`$item.Key): `$(`$item.Value) events" -ForegroundColor Gray
            }
        }
        
        if (`$uniqueLogs.Count -gt 0) {
            `$allCollectedLogs[`$logName] = `$uniqueLogs.Values
        }
        
    } catch {
        Write-Host "  Error collecting events: `$_" -ForegroundColor Red
        continue
    }
}

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "Formatting collected logs for output..." -ForegroundColor Yellow

`$unrelatedLogs = "### Non-relevant(benign) Logs ###`n"
`$totalLogCount = 0

foreach (`$logName in `$allCollectedLogs.Keys) {
    `$logs = `$allCollectedLogs[`$logName]
    
    if (`$logs.Count -eq 0) {
        continue
    }
    
    Write-Host "`nAdding `$(`$logs.Count) logs from `$logName" -ForegroundColor Green
    
    `$unrelatedLogs += "`n### `$logName ###`n"
    
    foreach (`$xmlString in `$logs) {
        try {
            `$xmlDoc = [xml]`$xmlString
        } catch {
            continue
        }
        
        `$unrelatedLogs += "#### log ####`n"
        `$totalLogCount++
        
        # System fields
        if (`$xmlDoc.Event.System) {
            foreach (`$node in `$xmlDoc.Event.System.ChildNodes) {
                `$key = `$node.Name
                if (`$detectionFields -contains `$key -and `$key -ne 'Channel') {
                    `$value = `$node.InnerText
                    if (`$value) {
                        `$unrelatedLogs += "`${key}: `$value`n"
                    }
                }
            }
        }
        
        # EventData fields
        if (`$xmlDoc.Event.EventData.Data) {
            `$addedFields = @{}
            
            foreach (`$dataNode in `$xmlDoc.Event.EventData.Data) {
                if (`$dataNode.Name) {
                    `$key = `$dataNode.Name
                    `$value = `$dataNode.'#text'
                    
                    if (`$addedFields.ContainsKey(`$key)) {
                        continue
                    }
                    
                    if (`$detectionFields -contains `$key -and `$value) {
                        if (`$value.Length -gt 300) {
                            `$value = `$value.Substring(0, 297) + "..."
                        }
                        
                        `$unrelatedLogs += "`${key}: `$value`n"
                        `$addedFields[`$key] = `$true
                    }
                }
            }
        }
        
        `$unrelatedLogs += "`n"
    }
}

if (`$totalLogCount -lt 20) {
    Write-Host "`nAdding standard Windows events to reach minimum baseline..." -ForegroundColor Yellow
    
    `$extendedEndTime = Get-Date
    `$extendedStartTime = `$extendedEndTime.AddHours(-1)
    
    foreach (`$logName in @('System', 'Application')) {
        if (`$totalLogCount -ge 30) { break }
        
        try {
            `$additionalEvents = Get-WinEvent -FilterHashtable @{
                LogName = `$logName
                StartTime = `$extendedStartTime
                EndTime = `$extendedEndTime
            } -MaxEvents 20 -ErrorAction Stop
            
            `$addedCount = 0
            foreach (`$event in `$additionalEvents) {
                if (`$totalLogCount -ge 30 -or `$addedCount -ge 5) { break }
                
                `$xml = `$event.ToXml()
                `$xmlDoc = [xml]`$xml
                
                `$unrelatedLogs += "#### log ####`n"
                `$unrelatedLogs += "EventID: `$(`$event.Id)`n"
                
                if (`$event.Message) {
                    `$shortMessage = `$event.Message.Split("`n")[0]
                    if (`$shortMessage.Length -gt 100) {
                        `$shortMessage = `$shortMessage.Substring(0, 97) + "..."
                    }
                    `$unrelatedLogs += "Message: `$shortMessage`n"
                }
                
                `$unrelatedLogs += "`n"
                `$totalLogCount++
                `$addedCount++
            }
            
            if (`$addedCount -gt 0) {
                Write-Host "  Added `$addedCount additional events from `$logName" -ForegroundColor Gray
            }
        } catch {
            continue
        }
    }
}

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "Final Statistics:" -ForegroundColor Yellow
Write-Host "  Total unique logs collected: `$totalLogCount" -ForegroundColor Green

`$outputPath = Join-Path `$cfgDir 'unrelatedLogs.txt'
`$unrelatedLogs | Out-File -FilePath `$outputPath -Encoding utf8

Write-Host "  Output saved to: `$outputPath" -ForegroundColor Green

@{
    Success = `$true
    LogCount = `$totalLogCount
    OutputPath = `$outputPath
} | ConvertTo-Json
"@
    
    # Save baseline script temporarily
    $baselineScript | Out-File -FilePath $logCollectorPath -Encoding utf8
    
    # Execute baseline collection
    try {
        Write-Host "Executing baseline collection script..." -ForegroundColor Cyan
        
        & powershell.exe -ExecutionPolicy Bypass -File $logCollectorPath -StartTime $baselineStartTimeStr -EndTime $baselineEndTimeStr
        
        $configPath = Join-Path $PSScriptRoot "config"
        $unrelatedPath = Join-Path $configPath "unrelatedLogs.txt"
        
        if (Test-Path $unrelatedPath) {
            $content = Get-Content $unrelatedPath -Raw
            $logCount = ([regex]::Matches($content, "#### log ####")).Count
            
            Write-Host ""
            Write-Host "===== Baseline Collection Summary =====" -ForegroundColor Yellow
            Write-Host "  Total logs collected: $logCount" -ForegroundColor Cyan
            
            $sysmonCount = 0
            $securityCount = 0
            $systemCount = 0
            $appCount = 0
            
            if ($content -match "### Microsoft-Windows-Sysmon/Operational ###([\s\S]*?)(?:###|$)") {
                $sysmonSection = $Matches[1]
                $sysmonCount = ([regex]::Matches($sysmonSection, "#### log ####")).Count
            }
            if ($content -match "### Security ###([\s\S]*?)(?:###|$)") {
                $securitySection = $Matches[1]
                $securityCount = ([regex]::Matches($securitySection, "#### log ####")).Count
            }
            if ($content -match "### System ###([\s\S]*?)(?:###|$)") {
                $systemSection = $Matches[1]
                $systemCount = ([regex]::Matches($systemSection, "#### log ####")).Count
            }
            if ($content -match "### Application ###([\s\S]*?)(?:###|$)") {
                $appSection = $Matches[1]
                $appCount = ([regex]::Matches($appSection, "#### log ####")).Count
            }
            
            if ($sysmonCount -gt 0) { Write-Host "  - Sysmon logs: $sysmonCount" -ForegroundColor Gray }
            if ($securityCount -gt 0) { Write-Host "  - Security logs: $securityCount" -ForegroundColor Gray }
            if ($systemCount -gt 0) { Write-Host "  - System logs: $systemCount" -ForegroundColor Gray }
            if ($appCount -gt 0) { Write-Host "  - Application logs: $appCount" -ForegroundColor Gray }
            
            if ($logCount -lt 5) {
                Write-Warning "Only $logCount logs collected. This might not be enough for effective baseline."
                Write-Host "Consider:" -ForegroundColor Yellow
                Write-Host "  1. Ensure Sysmon is installed and running" -ForegroundColor White
                Write-Host "  2. Run the script with Administrator privileges" -ForegroundColor White
                Write-Host "  3. Increase the collection time" -ForegroundColor White
            } else {
                Write-Host ""
                Write-Host "Baseline collection successful!" -ForegroundColor Green
                Write-Host "  Baseline logs provide examples of normal system activity." -ForegroundColor Cyan
                Write-Host "  This helps the LLM distinguish legitimate from malicious behavior." -ForegroundColor Cyan
            }
        } else {
            throw "Baseline log file was not created"
        }
    } catch {
        Write-Error "Failed to collect baseline: $_"
        Write-Host "Creating default unrelatedLogs.txt..." -ForegroundColor Yellow
        
        # Create default unrelatedLogs.txt if baseline collection fails
        $defaultUnrelated = @'
### Non-relevant(benign) Logs ###
#### log ####
EventID: 1
Level: 4
Keywords: 0x8000000000000000
Channel: Microsoft-Windows-Sysmon/Operational
ProcessId: 4356
Image: C:\Windows\System32\svchost.exe
Description: Host Process for Windows Services
Company: Microsoft Corporation
OriginalFileName: svchost.exe
CommandLine: C:\Windows\System32\svchost.exe -k LocalService
User: NT AUTHORITY\LOCAL SERVICE
'@
        $configPath = Join-Path $PSScriptRoot "config"
        if (-not (Test-Path $configPath)) {
            New-Item -ItemType Directory -Path $configPath -Force | Out-Null
        }
        $defaultUnrelated | Out-File -FilePath (Join-Path $configPath "unrelatedLogs.txt") -Encoding utf8
    }
    
    # Clean up temporary script
    if (Test-Path $logCollectorPath) {
        Remove-Item $logCollectorPath -Force
    }
    
} else {
    Write-Host "Skipping baseline collection." -ForegroundColor Yellow
    Write-Host "Using default unrelatedLogs.txt" -ForegroundColor Yellow
    
    # Create default unrelatedLogs.txt
    $configPath = Join-Path $PSScriptRoot "config"
    if (-not (Test-Path $configPath)) {
        New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    }
    
    $defaultUnrelated = @'
### Non-relevant(benign) Logs ###
#### log ####
EventID: 1
Level: 4
Keywords: 0x8000000000000000
Channel: Microsoft-Windows-Sysmon/Operational
ProcessId: 4356
Image: C:\Windows\System32\svchost.exe
Description: Host Process for Windows Services
Company: Microsoft Corporation
OriginalFileName: svchost.exe
CommandLine: C:\Windows\System32\svchost.exe -k LocalService
User: NT AUTHORITY\LOCAL SERVICE
'@
    $defaultUnrelated | Out-File -FilePath (Join-Path $configPath "unrelatedLogs.txt") -Encoding utf8
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "          SETUP COMPLETED SUCCESSFULLY!         " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host '1. Run "npm install" to install Node.js dependencies' -ForegroundColor White
Write-Host '2. Run "npm run dev" to start the application' -ForegroundColor White
Write-Host "3. Open http://localhost:3000 in your browser" -ForegroundColor White
Write-Host ""
Write-Host "Happy threat hunting with SigmaOptimizer!" -ForegroundColor Yellow