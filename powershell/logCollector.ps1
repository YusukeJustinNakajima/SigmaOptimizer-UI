# logCollector.ps1

param(
    [string]$Mode        = "cmd",       # cmd / ps / cal
    [string]$Command     = "",
    [string]$LogSources  = "sysmon"
)

Import-Module Invoke-ArgFuscator

$cfgDir = Join-Path $PSScriptRoot 'config'

$unrelatedPath  = Join-Path $cfgDir 'unrelatedLogs.txt'

if (Test-Path $unrelatedPath) {
    $unrelatedLogs = Get-Content $unrelatedPath -Raw
} else {
    $unrelatedLogs = ""
}

$detectionPath  = Join-Path $cfgDir 'detection_fields.txt'
if (-not (Test-Path $detectionPath)) {
    Write-Error "detection_fields.txt not found"; exit 1
}
$detectionFields = Get-Content $detectionPath

# Remove all files in the logs folder before execution
$logDir = "$PSScriptRoot\logs"
if (Test-Path $logDir) {
    Remove-Item "$logDir\*" -Force -Recurse
} else {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$commandCount = 1

$IsObfuscation = $false
$ObfuscateCommand = @()

if ($Mode -eq "powershell") {
    $Mode = "ps"
    Write-Host "Mode converted from 'powershell' to 'ps'" -ForegroundColor Yellow
}

if ($Mode -eq "ps") {
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "`"$Command`"" -Wait

    try {
        $ObfuscateCommand = Invoke-ArgFuscator -Command $Command -n 1
        $IsObfuscation = $true
    } catch {
        $ObfuscateCommand = @()
        $IsObfuscation = $false
    }
    
    if ($IsObfuscation -eq $true) {
        foreach ($obsCmd in $ObfuscateCommand) {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "`"$obsCmd`"" -Wait
            $commandCount++
        }
    }
} elseif ($Mode -eq "cmd") {
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$Command`"" -Wait

    try {
        $ObfuscateCommand = Invoke-ArgFuscator -Command $Command -n 1
        $IsObfuscation = $true
    } catch {
        $ObfuscateCommand = @()
        $IsObfuscation = $false
    }
    if ($IsObfuscation -eq $true) {
        foreach ($obsCmd in $ObfuscateCommand) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$obsCmd`"" -Wait
            $commandCount++
        }
    }
} elseif ($Mode -eq "cal") {
    # Wait for splunkd to start (check every 1 seconds)
    while (-not (Get-Process -Name "splunkd" -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 1
    }
    $startTimeObj = Get-Date
    $startTime = $startTimeObj.ToString("yyyy-MM-dd HH:mm:ss")
    $commandCount = 1
} else {
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "`"$Command`"" -Wait
}

Start-Sleep -Seconds 1

$requestedSources = $LogSources -split ','

$logSourceMapping = @{
    'sysmon' = 'Microsoft-Windows-Sysmon/Operational'
    'application' = 'Application'
    'security' = 'Security'
    'system' = 'System'
    'powershell' = 'Windows PowerShell'
    'powershell-operational' = 'Microsoft-Windows-PowerShell/Operational'
}


if ($Mode -eq "cal") {
    $logSources = @('Microsoft-Windows-Sysmon/Operational')
} else {
    [System.Collections.ArrayList]$logSources = @()
    
    foreach ($source in $requestedSources) {
        $source = $source.Trim().ToLower()
        
        if ($logSourceMapping.ContainsKey($source)) {
            if ($source -in @('powershell', 'powershell-operational') -and $Mode -ne "ps") {
                continue
            }
            [void]$logSources.Add($logSourceMapping[$source])
        }
    }
    
    if ($logSources.Count -eq 0) {
        [void]$logSources.Add('Microsoft-Windows-Sysmon/Operational')
    }

    $logSources = $logSources.ToArray()
}

Write-Host "Log sources count: $($logSources.Count)" -ForegroundColor Yellow
for ($i = 0; $i -lt $logSources.Count; $i++) {
    Write-Host "Log source [$i]: $($logSources[$i])" -ForegroundColor Cyan
}

if ($Mode -eq "cal") {
    $combinedXml = @{}
    $logName = "Microsoft-Windows-Sysmon/Operational"
    $parentPid = (Get-Process -Name "splunkd").Id
    $filterXPath = "*[EventData[Data[@Name='ParentProcessId']='$parentPid']]"
    
    try {
        $operationComplete = Read-Host "Is the MITRE Caldera Operation complete? (y/n)"
        while ($operationComplete -ne "y" -and $operationComplete -ne "yes") {
            Start-Sleep -Seconds 3
            $operationComplete = Read-Host "`nIs the MITRE Caldera Operation complete? (y/n)"
        }

        $endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        $sanitizedLogName = $logName -replace '[\\/]', '_'
        $evtxPath = "$logDir\$sanitizedLogName.evtx"
        wevtutil epl $logName $evtxPath 2> $null

        $events = Get-WinEvent -Path $evtxPath -FilterXPath $filterXPath | Where-Object { $_.TimeCreated -ge $startTimeObj }
        if ($events) {
            $logEntries = @()
            foreach ($event in $events) {
                $xml = $event.ToXml()
                $logEntries += $xml
            }
            if ($logEntries.Count -gt 0) {
                $combinedXml[$logName] = $logEntries
            }
        }
    } catch {
        # Error handling
    }
}
else {
    $endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    $combinedXml = @{}

    foreach ($logName in $logSources) {
        Write-Host "`nProcessing log source: $logName" -ForegroundColor Cyan
        
        try {
            $sanitizedLogName = $logName -replace '[\\/]', '_'
            $evtxPath = "$logDir\$sanitizedLogName.evtx"
            
            # Export EVTX using wevtutil
            Write-Host "Exporting $logName to $evtxPath" -ForegroundColor Gray
            $exportResult = wevtutil epl $logName $evtxPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to export: $exportResult" -ForegroundColor Red
                continue
            }
            
            $events = @()
            try {
                $events = Get-WinEvent -FilterHashtable @{
                    LogName   = $logName;
                    StartTime = $startTime;
                    EndTime   = $endTime
                } -ErrorAction Stop
                
                Write-Host "Found $($events.Count) total events in $logName" -ForegroundColor Green
                
                # EventIDごとの集計
                $eventIdCounts = $events | Group-Object -Property Id | Sort-Object Name
                Write-Host "Event ID distribution:" -ForegroundColor Yellow
                foreach ($group in $eventIdCounts) {
                    Write-Host "  EventID $($group.Name): $($group.Count) events" -ForegroundColor Gray
                }
                
            } catch {
                Write-Host "No events found: $_" -ForegroundColor Yellow
                continue
            }

            if ($events -and $events.Count -gt 0) {
                $logEntries = @()
                
                if ($logName -match "PowerShell") {
                    # Microsoft-Windows-PowerShell/Operational の場合、4104のみ
                    if ($logName -eq "Microsoft-Windows-PowerShell/Operational") {
                        $targetEvents = $events | Where-Object { $_.Id -in @(4104) }
                        Write-Host "Found $($targetEvents.Count) events with ID 4104" -ForegroundColor Cyan
                        
                        $addedCount = 0
                        $maxEvents = 10  # 上限10件
                        
                        foreach ($event in $targetEvents) {
                            if ($addedCount -ge $maxEvents) {
                                Write-Host "Reached limit of $maxEvents events" -ForegroundColor Yellow
                                break
                            }
                            
                            $xml = $event.ToXml()
                            $logEntries += $xml
                            $addedCount++
                            Write-Host "  Added EventID $($event.Id) (total: $addedCount)" -ForegroundColor Green
                        }
                    }

                    else {
                        $addedCount = 0
                        $maxEvents = 10 
                        
                        foreach ($event in $events) {
                            if ($addedCount -ge $maxEvents) {
                                Write-Host "Reached limit of $maxEvents events" -ForegroundColor Yellow
                                break
                            }
                            
                            $xml = $event.ToXml()
                            $logEntries += $xml
                            $addedCount++
                            Write-Host "  Added EventID $($event.Id) (total: $addedCount)" -ForegroundColor Green
                        }
                    }
                }
                else {
                    foreach ($event in $events) {
                        $xml = $event.ToXml()
                        
                        # Exclude logs containing "powershell" in cmd environment
                        if ($Mode -eq "cmd" -and $xml.ToLower() -match "powershell") {
                            continue
                        }
                        
                        $logEntries += $xml
                    }
                }
                
                Write-Host "Added $($logEntries.Count) entries to combinedXml" -ForegroundColor Green
                
                if ($logEntries.Count -gt 0) {
                    $combinedXml[$logName] = $logEntries
                }
            }
        } catch {
            #Write-Host "Error processing $logName: $_" -ForegroundColor Red
            continue
        }
    }
}

function Test-ShouldExcludeLog {
    param([xml]$xmlDoc)
    
    $excludePatterns = @(
        "conhost\.exe",
        "logCollector\.ps1",
        "Invoke-ArgFuscator",
        "wevtutil.*epl",
        "Get-WinEvent"
    )
    
    if ($xmlDoc.Event.System) {
        foreach ($node in $xmlDoc.Event.System.ChildNodes) {
            foreach ($pattern in $excludePatterns) {
                if ($node.InnerText -match $pattern) {
                    return $true
                }
            }
        }
    }
    
    if ($xmlDoc.Event.EventData) {
        foreach ($dataNode in $xmlDoc.Event.EventData.Data) {
            foreach ($pattern in $excludePatterns) {
                if ($dataNode.'#text' -match $pattern) {
                    return $true
                }
            }
        }
    }
    
    return $false
}


$finalLog = ""


foreach ($logName in $combinedXml.Keys) {

    $finalLog += "### $logName Log ###`n"
    $logIndex = 1
    
    foreach ($xmlString in $combinedXml[$logName]) {
        try {
            $xmlDoc = [xml]$xmlString
        } catch {
            $finalLog += "  [XML parse error]`n"
            continue
        }

        if (Test-ShouldExcludeLog -xmlDoc $xmlDoc) {
            continue
        }

        $finalLog += "#### log $logIndex ####`n"
        $logIndex++

        if ($xmlDoc.Event.System) {
            foreach ($node in $xmlDoc.Event.System.ChildNodes) {
                $key = $node.Name
                if ($detectionFields -contains $key) {
                    $value = $node.InnerText
                    $finalLog += "${key}: $value`n"
                }
            }
        }

        if ($logName -match "PowerShell") {

            $eventId = $xmlDoc.Event.System.EventID
            if ($eventId -is [System.Xml.XmlElement]) {
                $eventIdValue = $eventId.InnerText
            } else {
                $eventIdValue = $eventId
            }
            
            # EventID 4103: Module Logging
            if ($eventIdValue -eq "4103") {
                $payload = $xmlDoc.Event.EventData.SelectSingleNode("Data[@Name='Payload']")
                if ($payload -and $detectionFields -contains "Payload") {
                    $finalLog += "Payload: $($payload.InnerText)`n"
                }
                
                $contextInfo = $xmlDoc.Event.EventData.SelectSingleNode("Data[@Name='ContextInfo']")
                if ($contextInfo -and $detectionFields -contains "ContextInfo") {
                    $finalLog += "ContextInfo: $($contextInfo.InnerText)`n"
                }
            }
            
            # EventID 4104: Script Block Logging
            elseif ($eventIdValue -eq "4104") {
                # ScriptBlockText を取得
                $scriptBlockText = $xmlDoc.Event.EventData.SelectSingleNode("Data[@Name='ScriptBlockText']")
                if ($scriptBlockText -and $detectionFields -contains "ScriptBlockText") {
                    $finalLog += "ScriptBlockText: $($scriptBlockText.InnerText)`n"
                }
                
                $path = $xmlDoc.Event.EventData.SelectSingleNode("Data[@Name='Path']")
                if ($path -and $detectionFields -contains "Path") {
                    $finalLog += "Path: $($path.InnerText)`n"
                }

                $scriptBlockId = $xmlDoc.Event.EventData.SelectSingleNode("Data[@Name='ScriptBlockId']")
                if ($scriptBlockId -and $detectionFields -contains "ScriptBlockId") {
                    $finalLog += "ScriptBlockId: $($scriptBlockId.InnerText)`n"
                }
            }
        }

        if ($xmlDoc.Event.EventData) {
            foreach ($dataNode in $xmlDoc.Event.EventData.Data) {
                $key = $dataNode.Name
                if ($Mode -eq "cal" -and ($key -eq "ParentImage" -or $key -eq "ParentCommandLine")) {
                    continue
                }
                if ($detectionFields -contains $key) {
                    $value = $dataNode.'#text'
                    if ($value) {
                        $finalLog += "${key}: $value`n"
                    }
                }
            }
        }
        $finalLog += "`n"
    }
    
    $finalLog += "`n"
}

if ($unrelatedLogs) {
    $finalLog += $unrelatedLogs
}

if ($finalLog -eq "") {
    $finalLog = "No logs were collected for the specified time range and log sources.`n"
    $finalLog += "Requested sources: $($logSources -join ', ')`n"
    $finalLog += "Time range: $startTime to $endTime`n"
}

$finalLog | Out-File -FilePath "$PSScriptRoot\final_log.txt" -Encoding utf8

$publicLogsDir = "$PSScriptRoot\..\public\logs"
if (-not (Test-Path $publicLogsDir)) {
    New-Item -ItemType Directory -Path $publicLogsDir -Force | Out-Null
}

Copy-Item -Path "$PSScriptRoot\final_log.txt" -Destination "$publicLogsDir\final_log.txt" -Force

$result = [pscustomobject]@{
    Success      = $true
    FinalLogPath = "/logs/final_log.txt"
    StartTime    = "$startTime +09:00"
    EndTime      = "$endTime +09:00"
    LogSources   = $logSources -join ","
}

$result | ConvertTo-Json -Compress

exit 0