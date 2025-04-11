#Requires -Modules ServerEye.PowerShell.Helper
<#
    .SYNOPSIS
    Generate a list of customers and the number of sensors they have of one, multiple or all sensor types.

    .DESCRIPTION
    This script retrieves a list of all customers and the number of sensors they have of one, multiple or all sensor types.
    The sensor types can be specified by their ID, which can be found by clicking on the sensor in the OCC and checking the information tab on the right side of the screen.
    If no sensor types are provided, all sensor types of agents that exist at least once will be counted.

    .PARAMETER SensorTypeIDs
    The IDs of the sensor types to count.
    This can be found by clicking on the sensor in the OCC and checking the information tab on the right side of the screen.

    .PARAMETER ExportPath
    The path to export the data to. If not provided, the data will be displayed in the console.
    Note: The Export-Excel module is required for this to work. Install it via "Install-Module ImportExcel" if you don't have it yet.

    .PARAMETER AuthToken
    A servereye API-Key to use for authentication. The API-Key needs to have access to all customers that should be counted.

    .EXAMPLE
    PS> .\Get-SensorTypeCountPerCustomer.ps1 -SensorTypeIDs "9BB0B56D-F012-456f-8E20-F3E37E8166D9", "802387A2-25B4-464e-888E-F753808A924A" -AuthToken "1a2b3c4d-5e6f-7g8h-9i0j-1k2l3m4n5o6p"

    Generate a list of how many "Drive Space" and "Windows Reboot Detection" Sensors each customer has.
    
    Example Output:

    Customer                   Drive Space Windows Reboot Detection
    --------                   ----------- ------------------------
    Mr.Sensor's Demolabor                3                        3
    servereye Helpdesk                   5                        8
    Exchange Company                     5                        3
    Systemmanager IT                     4                        0
    SE Landheim                          2                        0

    .EXAMPLE
    PS> .\Get-SensorTypeCountPerCustomer.ps1 -AuthToken "1a2b3c4d-5e6f-7g8h-9i0j-1k2l3m4n5o6p" -ExportPath "C:\Temp\SensorTypeCount.xlsx"

    Generate a list of how many sensors of all types each customer has and export it to an Excel file.
    Note: It is recommended to use the ExportPath parameter when generating a list of all sensor types, as the output can be quite large. The console most likely won't be able to display all of it.

    .NOTES
    Author  : servereye
    Version : 1.1
#>

param (
    [Parameter(Mandatory=$false)]
    [string[]]$SensorTypeIDs,

    [Parameter(Mandatory=$false)]
    [string]$ExportPath,

    [Parameter(Mandatory=$true)]
    [Alias("ApiKey")]
    [string]$AuthToken
)

if ($ExportPath -and (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue))) {
    Write-Error "The ImportExcel module is required for exporting to Excel. Install it via 'Install-Module ImportExcel' if you don't have it yet."
    exit
}

$Agents = Get-SeApiMyNodesList -Filter agent -AuthToken $AuthToken
$CustomerIds = $Agents | Select-Object -ExpandProperty customerId -Unique
$SensorTypeList = Get-SeApiAgentTypeList -AuthToken $AuthToken

if (-not $SensorTypeIDs) {
    # If no SensorTypeIDs are provided by the user, get all sensor types of agents that exist at least once
    $SensorTypeIDs = $Agents | Select-Object -ExpandProperty agentType -Unique
}

$CustomerSensorCounts = @()
foreach ($CustomerId in $CustomerIds) {
    $Customer = [PSCustomObject]@{
        Customer = Get-SeApiCustomer -CId $CustomerId -AuthToken $AuthToken | Select-Object -ExpandProperty companyName
    }
    foreach ($SensorTypeID in $SensorTypeIDs) {
        $SensorTypeName = $SensorTypeList | Where-Object -Property agentType -eq $SensorTypeID | Select-Object -ExpandProperty defaultName
        $SensorCount = $Agents | Where-Object { $_.customerId -eq $CustomerId -and $_.agentType -eq $SensorTypeID } | Measure-Object | Select-Object -ExpandProperty Count
        if ($null -ne $SensorTypeName -and $SensorTypeName -ne "") {
            $Customer | Add-Member -NotePropertyName $SensorTypeName -NotePropertyValue $SensorCount
        }
    }
    $CustomerSensorCounts += $Customer
}

if ($ExportPath) {
    $CustomerSensorCounts | Export-Excel -Path $ExportPath
} else {
    $CustomerSensorCounts | Format-Table -AutoSize
}
