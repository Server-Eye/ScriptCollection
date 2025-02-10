#Requires -Module ServerEye.Powershell.Helper

<#
    .SYNOPSIS
    Adds services to the ignore list of multiple Windows Service Health sensors of a single or multiple customers.
        
    .DESCRIPTION
    You can find all details regarding the usage of the script here:
    https://servereye.freshdesk.com/support/solutions/articles/14000149415-windows-dienst-gesundheit-ausschl%C3%BCsse-in-masse-definieren

    .PARAMETER customerId 
    ID of the Customer

    .PARAMETER PathToIgnoreCSV 
    Path to the CSV with a List of the Services, please use Services as the heading in the CSV.
    This parameter is optional.

    .NOTES
    Author  : servereye
    Version : 1.1
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)]
    $customerId,
    [Parameter(Mandatory = $false)]
    $PathToIgnoreCSV,
    [Parameter(ValueFromPipeline = $true)]
    [alias("ApiKey", "Session")]
    $AuthToken
)

$AuthToken = Test-SEAuth -AuthToken $AuthToken
$AgentType = "43C5B1C4-EF06-4117-B84A-7057EA3B31CF"
$NodesList = Get-SeApiMyNodesList -Filter customer, agent, container -AuthToken $AuthToken -listType object
# Combine both customer and managedCustomers into one object, since otherwise we would miss out on the distributor customer
$customers = $NodesList.customer + $NodesList.managedCustomers
$containers = $NodesList.container

if ($customerId) {
    $customers = $customers | Where-Object { $_.id -eq $customerId }
}


# Load all sensorhubs of the selected customer
$customerSensorhubList = $containers | Where-Object { $_.subtype -eq 2 -and $customers.id -contains $_.customerid }

Clear-Host
$tagList = [PSCustomObject]@{
    id       = 0
    name     = "All Sensorhubs of the customer - Don't filter by tag"
    readonly = $false
}

foreach ($sensorhub in $customerSensorhubList) {
    foreach ($tag in $sensorhub.tags) {
        if ($tagList.Name -notcontains $tag.name) {
            $tagList = [Array]$tagList + $tag
        }
    }
}

if ($customers.count -ge 1) {
    Write-Host "Selected customers:" ($customers.name -join ", ") -ForegroundColor Cyan
}
else {
    Write-Host "Selected customer:" $customers.name -ForegroundColor Cyan
}

$i = 0
Write-Host "Which Sensorhubs should the exclusion rule be set on? Choose the desired tag from the list:" -ForegroundColor Yellow
foreach ($tag in $tagList) {
    Write-Host $i ":" $tag.Name
    $i += 1
}
$AddtagInput = Read-Host -Prompt "Enter the number of the tag:"

$selectedAddTag = $tagList[$AddtagInput]
if (!$selectedAddTag) {
    Write-Error "Invalid input!"
    exit 1
}
elseif ($selectedAddTag.id -eq 0) {
    $sensorhubsToUpdate = $customerSensorhubList
}
else {
    $i = 0
    Write-Host "Which Sensorhubs should the exclusion rule NOT be set for? Choose the desired tag from the list:" -ForegroundColor Yellow
    foreach ($tag in $tagList) {
        Write-Host $i ":" $tag.Name
        $i += 1
    }
    $RemovetagInput = Read-Host -Prompt "Enter the number of the tag:"
    $selectedRemoveTag = $tagList[$RemovetagInput]
    if (!($selectedRemoveTag)) {
        Write-Error "Invalid input!"
        exit 1
    }
    elseif ($selectedRemoveTag -eq 0) {
        $sensorhubsToUpdate = $customerSensorhubList | Where-Object { $_.tags.Id -contains $selectedAddTag.id }
    }
    else {
        $sensorhubsToUpdate = $customerSensorhubList | Where-Object { $_.tags.Id -contains $selectedAddTag.id -and $_.tags.Id -notcontains $selectedRemoveTag.id }
    }
}

if (!$sensorhubsToUpdate) {
    Write-Host "$($sensorhubsToUpdate.Count) Sensorhubs with your chosen tag combination:" -ForegroundColor Cyan
    exit
}
else {
    $Agents = $NodesList.agent | Where-Object { $_.subtype -eq $AgentType -and $sensorhubsToUpdate.id -contains $_.parentId }
    Clear-Host
    if ($agents.count -eq 0) {
        Write-Host "$($sensorhubsToUpdate.Count) Sensorhubs with your chosen tag combination; $($agents.count) of these have the Windows Service Health Sensor, no changes need to be made here." -ForegroundColor Cyan
        exit
    }
    else {
        Write-Host "$($sensorhubsToUpdate.Count) Sensorhubs with your chosen tag combination; $($agents.count) of these have the Windows Service Health Sensor." -ForegroundColor Cyan
        Write-Host "Please enter the service names (service names, not display names, e.g. CCService) that should be added to the exception list - Then press enter on an empty line to continue:" -ForegroundColor Yellow
        if ($PathToIgnoreCSV) {
            $pathsInput = (Import-csv -Path $PathToIgnoreCSV).Services
        }
        else {
            $pathsInput = New-Object System.Collections.ArrayList
            $repeatInput = $true
        }
        do {
            $pathInput = Read-Host -Prompt "Service"
            if ([string]::IsNullOrEmpty($pathInput)) {
                if ($pathsInput.Count -eq 0) {
                    Write-Host "You have to enter at least one service!" -ForegroundColor Red
                }
                else {
                    $repeatInput = $false
                }
            }
            else {
                $pathsInput.Add($pathInput) | Out-Null
            }
        } while ($repeatInput -eq $true) 
    }
}


Clear-Host
$count = 0
foreach ($sensorhub in $sensorhubsToUpdate) {
    # Load all AntiRansom agents
    $Agents = $NodesList.agent | Where-Object { $_.Type -eq 3 -and $_.parentId -eq $sensorhub.id -and $_.subtype -eq $AgentType }
    foreach ($agent in $agents) {
        # Get the current path settings of the agent
        $currentPaths = (Get-SeApiAgentSettingList -AuthToken $AuthToken -AId $agent.id | Where-Object key -eq "serviceList").value

        $newClientPaths = $currentPaths

        if ([string]::IsNullOrEmpty($currentPaths)) {
            $newClientPaths = [string]::Join('|,|', $pathsInput)
        }
        else {

            $pathsArray = $currentPaths.Split("|,|")
            foreach ($path in $pathsInput) {
                # Check for existings paths
                if (!$pathsArray.contains($path)) {
                    $newClientPaths = $newClientPaths + "|,|" + $path
                    Write-Debug ("Added $path")
                }
                else {
                    Write-Debug ("Skip $path")
                }
            }
        }

        if ($currentPaths -ne $newClientPaths) {
            $count += 1
            Set-SeApiAgentSetting -AuthToken $AuthToken -AId $agent.id -key "serviceList" -value $newClientPaths | Out-Null
            Write-Host "Exception for $($sensorhub.name) has been added" -ForegroundColor Green
            Write-Debug ("New paths: $newClientPaths")
        }
        else {
            Write-Host "Skipped $($sensorhub.name)" -ForegroundColor DarkYellow
        }
    }
}

Write-Host "Added exceptions for a total of $count sensors." -ForegroundColor Cyan
Write-Host "Done. Bye!" -ForegroundColor Green