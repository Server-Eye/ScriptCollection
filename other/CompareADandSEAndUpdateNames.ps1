#Requires -Modules ServerEye.Powershell.Helper

<# 
    .SYNOPSIS
    Compares systems in the Active Directory and the OCC.

    .DESCRIPTION
    Checks if servereye is installed on all systems in the Active Directory, or if duplicate systems are present in the OCC.

    .PARAMETER ApiKey
    The ApiKey of a user that is managing the customer you want to check

    .PARAMETER CustomerID
    The CustomerID of the customer (can be found in the URL bar behind /customer/ when selecting a customer via the customer list in the OCC)
    
    .PARAMETER ADCheck
    Checks if all systems in the OCC are also listed in the Active Directory

    .PARAMETER SECheck
    Checks if all systems in the Active Directory are also listed in the OCC

    .PARAMETER UpdateSensorhubNames
    Updates the names of all Sensorhubs in the OCC which don't match the hostname of the system

    .NOTES
    Author  : servereye
    Version : 1.1
    
    .EXAMPLE
    Call with Session via Connect-SESession and check Active Directory for Systems which exist in the Active Directory, but not in the OCC:
    PS> Connect-SESession | CompareADandSEAndUpdateNames.ps1 -CustomerID "ID of the Customer" -SECheck

    .EXAMPLE
    Call with API Key and check Active Directory for Systems which exist in the OCC, but not in the Active Directory:
    PS> .\CompareADandSEAndUpdateNames.ps1 -ApiKey "yourApiKey" -CustomerID "ID of the Customer" -ADCheck

    .EXAMPLE
    Call with API Key and update the names of all Sensorhubs in the OCC which don't match the hostname of the system
    PS> .\CompareADandSEAndUpdateNames.ps1 -ApiKey "yourApiKey" -CustomerID "ID of the Customer" -UpdateSensorhubNames
#>

[CmdletBinding(DefaultParameterSetName="ADCheck")]
Param(
    [Parameter(ValueFromPipeline = $True)]
    [alias("ApiKey", "Session")]
    $AuthToken,
    [Parameter(Mandatory = $True)]
    $CustomerID,
    [Parameter(Mandatory = $False,ParameterSetName="ADCheck")]
    [Switch]$ADCheck,
    [Parameter(Mandatory = $False,ParameterSetName="SECheck")]
    [Switch]$SECheck,
    [Parameter(Mandatory = $False,ParameterSetName="UpdateSensorhubNames")]
    [Switch]$UpdateSensorhubNames
)

$AuthToken = Test-SEAuth -AuthToken $AuthToken

if ($SECheck.IsPresent -eq $True -or $ADCheck.IsPresent -eq $True) {
    $diff = Get-ADComputer -Filter * -Property Name, IPv4Address
    $reftmp = Get-SeApiMyNodesList -Filter container -AuthToken $AuthToken | Where-Object {$_.customerId -eq $CustomerID -and $_.Subtype -eq 2}
    $ref = $reftmp | Select-Object -Unique -Property Name
    $double = Compare-Object -ReferenceObject $ref -DifferenceObject $reftmp -Property Name
    $comp = Compare-Object -ReferenceObject $ref -DifferenceObject $diff -Property Name

    if ($double) {
        Write-Output "Duplicate systems in OCC:"
        (($double | Where-Object Sideindicator -eq "=>").Name)
    }

    if ($SECheck.IsPresent -eq $True) {
        Write-Output "`nThe following systems are in the Active Directory but not in the OCC:"
        (($comp | Where-Object Sideindicator -eq "=>").Name)
    }

    if ($ADCheck.IsPresent -eq $True) {
        Write-Output "`nThe following systems are in the OCC but do not exist in the Active Directory:"
        (($comp | Where-Object Sideindicator -eq "<=").Name)
    }
}

if ($UpdateSensorhubNames.IsPresent -eq $True) {
    $Sensorhubs = Get-SESensorhub -CustomerId $CustomerID -AuthToken $AuthToken
    Write-Host "Updating Sensorhub names which don't match the systems hostname:"
    foreach ($Sensorhub in $Sensorhubs) {
        if ($Sensorhub.Name -ne $Sensorhub.Hostname) {
            Write-Output "$($Sensorhub.Name) to $($Sensorhub.Hostname)"
            Set-SeApiContainer -CId $Sensorhub.SensorhubId -Name $Sensorhub.Hostname -AuthToken $AuthToken | Out-Null
        }
    }
    Write-Host "All done!"
}