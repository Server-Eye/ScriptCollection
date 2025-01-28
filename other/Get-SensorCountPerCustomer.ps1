<#
    .SYNOPSIS
    Generate a list of customers and the number of sensors of a specific type that they have.

    .DESCRIPTION
    This script retrieves a list of all customers and the number of sensors of a specific type that they have.
    The Senso

    .PARAMETER SensorTypeID
    The ID of the sensor type to count.
    This can be found by clicking on the sensor in the OCC and checking the information tab on the right side of the screen.

    .PARAMETER AuthToken
    A servereye API-Key to use for authentication. The API-Key needs to have access to all customers that should be counted.

    .EXAMPLE
    PS> .\SensorCountPerCustomer.ps1 -SensorTypeID "B2F9A3C1-4D5E-4b8a-9C7D-1234567890AB" -AuthToken "1a2b3c4d-5e6f-7g8h-9i0j-1k2l3m4n5o6p"
    Generate a list of how many PC Gesundheit Sensors each customer has.
    Example Output:

    Customer                   SensorCount
    --------                   -----------
    Mr.Sensor's Demolabor                6
    Exchange Company                    10
    Systemmanager IT                    28
    servereye Helpdesk                   7
    SE Landheim                          3

    .NOTES
    Author  : servereye
    Version : 1.0
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$SensorTypeID,

    [Parameter(Mandatory=$true)]
    [Alias("ApiKey")]
    [string]$AuthToken
)

$Agents = Get-SeApiMyNodesList -Filter agent -AuthToken $AuthToken
$CustomerIds = $Agents | Select-Object -ExpandProperty customerId -Unique
$CustomerSensorCounts = @()
foreach ($CustomerId in $CustomerIds) {
    $SensorCount = $Agents | Where-Object { $_.customerId -eq $CustomerId -and $_.agentType -eq $SensorTypeID } | Measure-Object | Select-Object -ExpandProperty Count
    $CustomerSensorCounts += [PSCustomObject]@{
        Customer = Get-SeApiCustomer -CId $CustomerId -AuthToken $AuthToken | Select-Object -ExpandProperty companyName
        "Sensor Count" = $SensorCount
    }
}
$CustomerSensorCounts | Format-Table -AutoSize