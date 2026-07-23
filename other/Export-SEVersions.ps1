<#
.SYNOPSIS
Exports the servereye versions of all sensorhubs to a CSV file.

.DESCRIPTION
This script retrieves the servereye versions of all sensorhubs and exports them to a CSV file.
By default only systems that are not up to date are included in the export. If the IncludeUpToDateSystems switch is specified, all systems will be included.

.PARAMETER ApiKey
The API key used to authenticate with the servereye API.

.PARAMETER IncludeUpToDateSystems
A switch parameter that, when specified, includes systems that are up to date in the exported CSV file.

.EXAMPLE
PS> .\Export-SEVersions.ps1 -ApiKey "your_api_key"
Exports the servereye versions of all sensorhubs that are not up to date to a CSV file.

.EXAMPLE
PS> .\Export-SEVersions.ps1 -ApiKey "your_api_key" -IncludeUpToDateSystems
Exports the servereye versions of all sensorhubs, including those that are up to date, to a CSV file.

.NOTES
Author  : Leon Zewe - servereye GmbH
Version : 1.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $ApiKey,

    [Parameter(Mandatory = $false)]
    [switch]
    $IncludeUpToDateSystems
)

try  {
    $containers = Invoke-RestMethod -Uri "https://api.server-eye.de/2/me/nodes?apiKey=$ApiKey&filter=container" -Method Get -ErrorAction Stop
    $sensorhubs = $containers | Where-Object -Property subtype -EQ 2
    $customers = Invoke-RestMethod -Uri "https://api.server-eye.de/2/me/nodes?apiKey=$ApiKey&filter=customer" -Method Get -ErrorAction Stop
    $currentSEVersion = Invoke-RestMethod -Uri "https://occ.server-eye.de/download/se/currentVersion" -Method Get -ErrorAction Stop
} 
catch {
    Write-Error "Failed to retrieve data from the servereye API, please check your ApiKey: `n$_"
    exit 1
}

$objects = @()
foreach ($sensorhub in $sensorhubs) {
    $objects += [PSCustomObject]@{
        Kunde = $customers | Where-Object { $_.id -eq $sensorhub.customerId } | Select-Object -ExpandProperty name
        System = $sensorhub.name
        'servereye Version' = $sensorhub.seVersion
        'Aktuell?' = if ($sensorhub.seVersion -eq $currentSEVersion -or $sensorhub.seVersion -gt $currentSEVersion) { 'Ja' } else { 'Nein' }
        'Zuletzt Online' = [datetime]::Parse($sensorhub.lastDate).ToString('dd.MM.yyyy HH:mm:ss')
    }
}
$sorted = if ($IncludeUpToDateSystems) {
    $objects | Sort-Object -Property 'Kunde', @{Expression = 'Aktuell?'; Descending = $true}
} else {
    $objects | Where-Object { $_.'Aktuell?' -eq 'Nein' } | Sort-Object -Property 'Kunde'
}
$csvContent = $sorted | ConvertTo-Csv -NoTypeInformation
@("sep=,") + $csvContent | Set-Content -Path "SEVersions.csv"

Write-Host "Export completed. The CSV file has been saved as 'SEVersions.csv' in the current directory." -ForegroundColor Green