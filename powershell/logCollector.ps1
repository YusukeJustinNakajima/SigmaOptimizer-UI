# logCollector.ps1

param(
    [string]$Mode        = "cmd",       # cmd / ps / cal
    [string]$Command     = ""
)

Import-Module Invoke-ArgFuscator

$cfgDir = Join-Path $PSScriptRoot 'config'

$unrelatedPath  = Join-Path $cfgDir 'unrelatedLogs.txt'

if (Test-Path $unrelatedPath) {
    $unrelatedLogs = Get-Content $unrelatedPath -Raw
} else {
    $unrelatedLogs = ""
    exit
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
    # Write-Output "All files in '$logDir' have been removed."
} else {
    New-Item -ItemType Directory -Path $logDir | Out-Null
    # Write-Output "Directory '$logDir' created."
}

$commandCount = 1
<#
if ($Mode -ne "cal") {
    # Write-Host "Block all external traffic to safely execute files and acquire logs`n" -ForegroundColor Green
    New-NetFirewallRule -DisplayName "Block Internet" -Direction Outbound -Action Block -Enabled True -Profile Any | Out-Null
}
#>
if ($Mode -eq "ps") {
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "`"$Command`"" -Wait

    if ($IsObfuscation -eq $true) {
        foreach ($obsCmd in $ObfuscateCommand) {
            Write-Output "Executing obfuscated command in PowerShell process: $obsCmd"
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
        $ObfuscateCommand = ""
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
    # Write-Host "'splunkd' process detected."
    $startTimeObj = Get-Date
    $startTime = $startTimeObj.ToString("yyyy-MM-dd HH:mm:ss")
    $commandCount = 1
} else {
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "`"$command`"" -Wait

    if ($IsObfuscation -eq $true) {
        foreach ($obsCmd in $ObfuscateCommand) {
            # Write-Output "Executing obfuscated command in PowerShell process: $obsCmd"
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "`"$obsCmd`"" -Wait
            $commandCount++
        }
    }
}

Start-Sleep -Seconds 2

if ($Mode -eq "cal") {
    $combinedXml = @{}
    $logName = "Microsoft-Windows-Sysmon/Operational"
    # Get process ID of splunkd
    $parentPid = (Get-Process -Name "splunkd").Id
    # Write-Host "Using ParentProcessId: $parentPid for log filtering." -ForegroundColor Cyan
    $filterXPath = "*[EventData[Data[@Name='ParentProcessId']='$parentPid']]"
    
    try {
        
        # Prompt the user to confirm that the MITRE Caldera Operation is complete
        $operationComplete = Read-Host "Is the MITRE Caldera Operation complete? (y/n)"
        while ($operationComplete -ne "y" -and $operationComplete -ne "yes") {
            # Write-Host "Operation not complete. Waiting..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
            $operationComplete = Read-Host "`nIs the MITRE Caldera Operation complete? (y/n)"
        }

        $endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Output EVTX files using wevtutil
        $sanitizedLogName = $logName -replace '[\\/]', '_'
        $evtxPath = "$logDir\$sanitizedLogName.evtx"
        wevtutil epl $logName $evtxPath 2> $null

        # Retrieve logs from the EVTX file since the specified start time
        $events = Get-WinEvent -Path $evtxPath -FilterXPath $filterXPath | Where-Object { $_.TimeCreated -ge $startTimeObj }
        if ($events) {
            $logEntries = @()
            foreach ($event in $events) {
                $xml = $event.ToXml()
                # Write-Host "$xml"
                $logEntries += $xml
            }
            if ($logEntries.Count -gt 0) {
                $combinedXml[$logName] = $logEntries
            }
        }
    } catch {
        # Error handling (e.g., output if necessary)
    }
}
else {
    $endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ($Mode -eq "cmd") {
        $logSources = @('Application', 'Security', 'System', 'Microsoft-Windows-Sysmon/Operational')
    }
    else {
        $logSources = @('Application', 'Security', 'System', 'Microsoft-Windows-Sysmon/Operational', 'Windows Powershell', 'Microsoft-Windows-PowerShell/Operational')
    }

    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    $combinedXml = @{}  # Hashtable to store logs (XML strings) for each log source

    foreach ($logName in $logSources) {
        try {
            $sanitizedLogName = $logName -replace '[\\/]', '_'
            $evtxPath = "$logDir\$sanitizedLogName.evtx"
            # Export EVTX using wevtutil
            wevtutil epl $logName $evtxPath 2> $null
            
            $events = Get-WinEvent -FilterHashtable @{
                LogName   = $logName;
                StartTime = $startTime;
                EndTime   = $endTime
            } -ErrorAction Stop

            if ($events) {
                $logEntries = @()  # Store logs for each log source
                $powershellCount = 0

                foreach ($event in $events) {
                    $xml = $event.ToXml()

                    # Exclude logs containing "powershell" in cmd environment
                    if ($envChoice -eq "cmd" -and $xml.ToLower() -match "powershell") {
                        continue
                    }

                    # Limit PowerShell logs to a maximum of 5
                    if ($logName -match "powershell") {
                        if ($powershellCount -ge 5) { continue }
                        $powershellCount++
                    }

                    $logEntries += $xml
                }
                if ($logEntries.Count -gt 0) {
                    $combinedXml[$logName] = $logEntries
                }
            }
        } catch {
            # Write-Output "Error retrieving logs from '$logName'"
        }
    }
}


$finalLog = ""
foreach ($logName in $combinedXml.Keys) {
    $finalLog += "### $logName Log ###`n"
    # Index variable to count log entries
    $logIndex = 1
    foreach ($xmlString in $combinedXml[$logName]) {
        try {
            $xmlDoc = [xml]$xmlString
        } catch {
            $finalLog += "  [XML parse error]`n"
            continue
        }

        # Check if conhost.exe is present in the log
        $containsConhost = $false

        # Check System node elements
        if ($xmlDoc.Event.System) {
            foreach ($node in $xmlDoc.Event.System.ChildNodes) {
                if ($node.InnerText -match "conhost.exe") {
                    $containsConhost = $true
                    break
                }
            }
        }

        # Check EventData node elements
        if ($xmlDoc.Event.EventData -and -not $containsConhost) {
            foreach ($dataNode in $xmlDoc.Event.EventData.Data) {
                if ($dataNode.'#text' -match "conhost.exe") {
                    $containsConhost = $true
                    break
                }
            }
        }

        # If conhost.exe is found, skip this log entry
        if ($containsConhost) {
            continue
        }

        # Append log if conhost.exe is NOT found
        $finalLog += "#### log $logIndex ####`n"
        $logIndex++

        # Append System node elements
        if ($xmlDoc.Event.System) {
            foreach ($node in $xmlDoc.Event.System.ChildNodes) {
                $key = $node.Name
                if ($detectionFields -contains $key) {
                    $value = $node.InnerText
                    $finalLog += "${key}: $value`n"
                }
            }
        }

        # Append EventData node elements
        if ($xmlDoc.Event.EventData) {
            foreach ($dataNode in $xmlDoc.Event.EventData.Data) {
                $key = $dataNode.Name
                # If environment is cal, skip ParentImage and ParentCommandLine
                if ($Mode -eq "cal" -and ($key -eq "ParentImage" -or $key -eq "ParentCommandLine")) {
                    continue
                }
                if ($detectionFields -contains $key) {
                    $value = $dataNode.'#text'
                    $finalLog += "${key}: $value`n"
                }
            }
        }
        $finalLog += "`n"
    }
    $finalLog += "`n"
}

# Append unrelated logs to final_log
$finalLog += "`n" + $unrelatedLogs

# Save to file
$finalLog | Out-File -FilePath "$PSScriptRoot\final_log.txt" -Encoding utf8
Copy-Item -Path "$PSScriptRoot\final_log.txt" -Destination "$PSScriptRoot\..\public\logs\final_log.txt"
# Write-Output "The logs, including unrelated logs, have been saved to final_log.txt."

$result = [pscustomobject]@{
    Success      = $true
    FinalLogPath = "/logs/final_log.txt"
    StartTime    = "$startTime +09:00"
    EndTime      = "$endTime +09:00"
}

$result | ConvertTo-Json -Compress

exit 0