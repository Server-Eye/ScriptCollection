#Requires -Modules ImportExcel
<#
    .SYNOPSIS
    Finds sensors with ping-pong state changes (rapid OK/ERROR flapping) and exports results to Excel.

    .DESCRIPTION
    This script checks all agents' state history for ping-pong scenarios where within a given timeframe,
    the sensor has changed from OK to ERROR (and back) multiple times. Results are exported to an Excel file
    showing customer name, sensorhub name, sensor name, number of state changes, and duration of each state.

    .PARAMETER ApiKey
    The servereye API key for authentication.

    .PARAMETER MinStateChanges
    Minimum number of state changes within the timeframe to be considered a ping-pong scenario. Default: 5

    .PARAMETER TimeframeDays
    Number of days to look back for state changes. Default: 7

    .PARAMETER ExportPath
    Path for the Excel export file. Default: current directory with timestamp.

    .PARAMETER StateLimit
    Maximum number of state history entries to retrieve per agent. Default: 100

    .EXAMPLE
    .\Find-PingPongSensors.ps1 -ApiKey "your-api-key" -MinStateChanges 4 -TimeframeDays 14

    .NOTES
    Author  : Leon Zewe - servereye GmbH
    Version : 1.0
#>

#Requires -Modules ImportExcel
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [Parameter()]
    [ValidateRange(2, 1000)]
    [int]$MinStateChanges = 5,

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$TimeframeDays = 7,

    [Parameter()]
    [string]$ExportPath = (Join-Path -Path (Get-Location) -ChildPath ("PingPong_Sensors_{0:yyyy-MM-dd_HH-mm-ss}.xlsx" -f (Get-Date))),

    [Parameter()]
    [ValidateRange(10, 1000)]
    [int]$StateLimit = 100
)

function Invoke-SeApiWithRetry {
    param (
        [string]$Uri,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 3
    )

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            return Invoke-RestMethod -Uri $Uri -Method Get -ErrorAction Stop
        }
        catch {
            $attempt++
            if ($attempt -ge $MaxRetries) {
                Write-Warning "Failed to call $Uri after $MaxRetries attempts: $_"
                return $null
            }
            Write-Verbose "Retry $attempt for $Uri - waiting ${DelaySeconds}s..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# --- Build lookup tables ---
Write-Host "Retrieving customers..." -ForegroundColor Cyan
$customerNodes = Invoke-SeApiWithRetry -Uri "https://api.server-eye.de/2/me/nodes?apiKey=$ApiKey&filter=customer"
$customerLookup = @{}
foreach ($c in $customerNodes) {
    $customerLookup[$c.id] = $c.name
}

Write-Host "Retrieving containers..." -ForegroundColor Cyan
$containerNodes = Invoke-SeApiWithRetry -Uri "https://api.server-eye.de/2/me/nodes?apiKey=$ApiKey&filter=container"
$containerLookup = @{}
foreach ($cont in $containerNodes) {
    $containerLookup[$cont.id] = $cont.name
}

# --- Get all agents ---
Write-Host "Retrieving all agents..." -ForegroundColor Cyan
$allAgents = Invoke-SeApiWithRetry -Uri "https://api.server-eye.de/2/me/nodes?apiKey=$ApiKey&filter=agent"

if (-not $allAgents -or $allAgents.Count -eq 0) {
    Write-Error "No agents found. Check your API key permissions."
    return
}

Write-Host "Found $($allAgents.Count) agents. Checking state history..." -ForegroundColor Green

# --- Analyze each agent ---
$cutoffDate = (Get-Date).AddDays(-$TimeframeDays).ToUniversalTime()
$results = [System.Collections.ArrayList]::new()
$pingPongDetails = [System.Collections.ArrayList]::new()
$counter = 0

foreach ($agent in $allAgents) {
    $counter++
    Write-Progress -Activity "Checking state history" -Status "Agent $counter of $($allAgents.Count): $($agent.name)" -PercentComplete (($counter / $allAgents.Count) * 100)

    $states = Invoke-SeApiWithRetry -Uri "https://api.server-eye.de/2/agent/$($agent.id)/state?apiKey=$ApiKey&limit=$StateLimit"

    if (-not $states -or $states.Count -lt $MinStateChanges) {
        continue
    }

    # Filter states within timeframe
    $recentStates = $states | Where-Object {
        [DateTime]::Parse($_.date, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime() -ge $cutoffDate
    } | Sort-Object { [DateTime]::Parse($_.date, [System.Globalization.CultureInfo]::InvariantCulture) }

    if (-not $recentStates -or $recentStates.Count -lt $MinStateChanges) {
        continue
    }

    $stateChangeCount = $recentStates.Count

    # This agent is a ping-pong candidate
    $customerName = $customerLookup[$agent.customerId]
    if (-not $customerName) { $customerName = $agent.customerId }

    $sensorhubName = $containerLookup[$agent.parentId]
    if (-not $sensorhubName) { $sensorhubName = $agent.parentId }

    # Calculate duration for each state
    $stateDetails = [System.Collections.ArrayList]::new()
    for ($i = 0; $i -lt $recentStates.Count; $i++) {
        $currentState = $recentStates[$i]
        $stateDate = [DateTime]::Parse($currentState.date, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()

        if ($i -lt ($recentStates.Count - 1)) {
            $nextDate = [DateTime]::Parse($recentStates[$i + 1].date, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
            $duration = $nextDate - $stateDate
        }
        else {
            $duration = (Get-Date).ToUniversalTime() - $stateDate
        }

        $stateLabel = if ($currentState.state -eq $true) { "ERROR" } else { "OK" }

        $durationText = if ($duration.TotalDays -ge 1) {
            "{0}d {1}h {2}m" -f [int]$duration.TotalDays, $duration.Hours, $duration.Minutes
        }
        elseif ($duration.TotalHours -ge 1) {
            "{0}h {1}m {2}s" -f [int]$duration.TotalHours, $duration.Minutes, $duration.Seconds
        }
        else {
            "{0}m {1}s" -f [int]$duration.TotalMinutes, $duration.Seconds
        }

        [void]$stateDetails.Add([PSCustomObject]@{
            Kunde        = $customerName
            Sensorhub    = $sensorhubName
            Sensor       = $agent.name
            "SensorURL" = "https://occ.server-eye.de/#/overview/agent/$($agent.id)/overview"
            Zeitpunkt    = $stateDate.ToLocalTime().ToString("dd.MM.yyyy HH:mm:ss")
            Status       = $stateLabel
            Dauer        = $durationText
            DauerSekunden = [math]::Round($duration.TotalSeconds, 0)
        })
    }

    # Summary entry
    $firstChange = [DateTime]::Parse($recentStates[0].date, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime().ToLocalTime()
    $lastChange = [DateTime]::Parse($recentStates[-1].date, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime().ToLocalTime()

    $firstStr = $firstChange.ToString("dd.MM.yyyy HH:mm")
    $lastStr = $lastChange.ToString("dd.MM.yyyy HH:mm")

    [void]$results.Add([PSCustomObject]@{
        Kunde              = $customerName
        Sensorhub          = $sensorhubName
        Sensor             = $agent.name
        "SensorURL"       = "https://occ.server-eye.de/#/overview/agent/$($agent.id)/overview"
        Statuswechsel      = $stateChangeCount
        Zeitraum           = "$firstStr - $lastStr"
        ErsterWechsel      = $firstChange.ToString("dd.MM.yyyy HH:mm:ss")
        LetzterWechsel     = $lastChange.ToString("dd.MM.yyyy HH:mm:ss")
    })

    # Add detail rows
    foreach ($detail in $stateDetails) {
        [void]$pingPongDetails.Add($detail)
    }
}
Write-Progress -Activity "Checking state history" -Completed

# --- Export to Excel ---
if ($results.Count -eq 0) {
    Write-Host "No ping-pong sensors found with $MinStateChanges+ state changes in the last $TimeframeDays days." -ForegroundColor Yellow
    return
}

Write-Host "`nFound $($results.Count) ping-pong sensor(s)!" -ForegroundColor Red

$results = $results | Sort-Object Statuswechsel -Descending

# Export summary sheet
$results | Export-Excel -Path $ExportPath -WorksheetName "Zusammenfassung" -AutoSize -BoldTopRow -FreezeTopRow -TableStyle Medium6

# Export details sheet
$pingPongDetails | Export-Excel -Path $ExportPath -WorksheetName "Details" -AutoSize -BoldTopRow -FreezeTopRow -TableStyle Medium4 -Append

Write-Host "`nExport saved to: $ExportPath" -ForegroundColor Green
