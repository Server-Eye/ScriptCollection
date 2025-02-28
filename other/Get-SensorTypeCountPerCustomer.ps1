<#
    .SYNOPSIS
    Generate a list of customers and the number of sensors they have of one or more sensortypes.

    .DESCRIPTION
    This script retrieves a list of all customers and the number of sensors they have of one or more sensortypes.

    .PARAMETER SensorTypeIDs
    The IDs of the sensor types to count.
    This can be found by clicking on the sensor in the OCC and checking the information tab on the right side of the screen.

    .PARAMETER AuthToken
    A servereye API-Key to use for authentication. The API-Key needs to have access to all customers that should be counted.

    .EXAMPLE
    PS> .\SensorCountPerCustomer.ps1 -SensorTypeID "9BB0B56D-F012-456f-8E20-F3E37E8166D9", "802387A2-25B4-464e-888E-F753808A924A" -AuthToken "1a2b3c4d-5e6f-7g8h-9i0j-1k2l3m4n5o6p"
    Generate a list of how many "Drive Space" and "Windows Reboot Detection" Sensors each customer has.
    
    Example Output:

    SensorType: Drive Space (9BB0B56D-F012-456f-8E20-F3E37E8166D9)

    Customer                   Sensor Count
    --------                   ------------
    Mr.Sensor's Demolabor                 3
    servereye Helpdesk                    5
    Exchange Company                      5
    Systemmanager IT                      4
    SE Landheim                           2


    SensorType: Windows Reboot Detection (802387A2-25B4-464e-888E-F753808A924A)

    Customer                   Sensor Count
    --------                   ------------
    Mr.Sensor's Demolabor                 3
    servereye Helpdesk                    8
    Exchange Company                      3
    Systemmanager IT                      0
    SE Landheim                           0

    .NOTES
    Author  : servereye
    Version : 1.0
#>

param (
    [Parameter(Mandatory=$true)]
    [string[]]$SensorTypeIDs,

    [Parameter(Mandatory=$true)]
    [Alias("ApiKey")]
    [string]$AuthToken
)

$Agents = Get-SeApiMyNodesList -Filter agent -AuthToken $AuthToken
$CustomerIds = $Agents | Select-Object -ExpandProperty customerId -Unique
$SensorTypeList = Get-SeApiAgentTypeList -AuthToken $AuthToken

foreach ($SensorTypeID in $SensorTypeIDs) {
    $CustomerSensorCounts = @()
    foreach ($CustomerId in $CustomerIds) {
        $SensorCount = $Agents | Where-Object { $_.customerId -eq $CustomerId -and $_.agentType -eq $SensorTypeID } | Measure-Object | Select-Object -ExpandProperty Count
        $CustomerSensorCounts += [PSCustomObject]@{
            Customer = Get-SeApiCustomer -CId $CustomerId -AuthToken $AuthToken | Select-Object -ExpandProperty companyName
            "Sensor Count" = $SensorCount
        }
    }
    $SensorTypeName = $SensorTypeList | Where-Object -Property agentType -eq $SensorTypeID | Select-Object -ExpandProperty defaultName
    Write-Host "SensorType: $SensorTypeName ($SensorTypeID)"
    $CustomerSensorCounts | Format-Table -AutoSize
}