<#
    .SYNOPSIS
    Rename Sensorhubs of a customer (or multiple customers) to current hostname
    
    .DESCRIPTION
    Renames a Sensorhub to the current hostname if the hostname is different from the container name.
    If the container name contains a string in brackets, it is added to the new name.

    .PARAMETER CustomerName
    Name of the customer whose Sensorhubs should be renamed. If not specified, the Sensorhubs of all customers will be renamed.

    .PARAMETER All
    Rename the Sensorhubs of all customers. If the parameter CustomerName is specified, this parameter is ignored.

    .PARAMETER Tag
    If a Sensorhub has this tag, it will not be renamed. If not specified, all Sensorhubs will be renamed.

    .PARAMETER Force
    If this parameter is specified, the script will not prompt the user to confirm before renaming all Sensorhubs.

    .PARAMETER AuthToken
    An API-Key of a user with the necessary permissions to access the customers and sensorhubs.

    .NOTES
    Author  : servereye
    Version : 1.0

    .EXAMPLE
    PS> .\Rename-SensorhubsToHostname.ps1 -All -Tag "Server" -AuthToken "AuthToken"
    Renames all Sensorhubs of the customer "servereye Helpdesk" that do not have the tag "Server" to the current hostname.

    .EXAMPLE
    PS> .\Rename-SensorhubsToHostname.ps1 -All -AuthToken "AuthToken"
    Renames all Sensorhubs of all customers to the current hostname.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [string]
    $CustomerName,

    [Parameter(Mandatory = $false)]
    [switch]
    $All,

    [Parameter(Mandatory = $false)]
    [string]
    $Tag,

    [Parameter(Mandatory = $false)]
    [switch]
    $Force,

    [Parameter(Mandatory = $true)]
    [Alias("ApiKey")]
    [string]
    $AuthToken
)

$nodes = Get-SeApiMyNodesList -ListType object -AuthToken $authtoken

# If a customer name is specified, get only the containers for that customer. Otherwise, get all containers for all customers
if ($CustomerName) {
    # Get the customer with the specified name
    $customer = $nodes.managedCustomers | Where-Object -Property name -eq $CustomerName
    # Get all containers of type "Sensorhub" (subtype 2) for the specified customer
    $containers = $nodes.container | Where-Object -Property customerId -eq $customer.Id | Where-Object -Property subtype -eq "2"
} elseif ($All) {
    if (-not $Force) {
        # Display a warning message and prompt the user to continue or exit
        $confirmation = Read-Host "WARNING: You are about to rename ALL Sensorhubs for ALL customers. Do you want to continue? (yes/no)"
        if ($confirmation -ne 'y' -or $confirmation -ne 'yes') {
            Write-Host "Operation cancelled by user." -ForegroundColor Red
            exit
        }
    }
    # Get all containers of type "Sensorhub" (subtype 2) for all customers
    $containers = $nodes.container | Where-Object -Property subtype -eq "2"
} else {
    Write-Host "Please specify a customer name or use the -All switch to rename the Sensorhubs of all customers." -ForegroundColor Red
    exit
}

foreach ($container in $containers) {
    # Move onto the next container if this one has the specified tag
    if ($container.tags.name -contains $Tag) {
        Write-Host "Sensorhub '$($container.name)' has tag '$Tag', continuing to next one" -ForegroundColor Yellow
        continue
    }
    # Get the hostname of the container so we can compare it to the name of the current container
    $hostname = (Get-SeApiContainer -CId $container.id -AuthToken $authtoken).machineName
    # If the hostname is different from the container name, rename the container
    if ($hostname -ne $container.name) {
        $newName = $hostname
        # If the container name contains a string in brackets, add it to the new name
        if ($container.name -match "\((.*?)\)") {
            $newName += " " + $matches[0]
        }
        # If the new name isn't the same as the current name, rename the container
        if ($newName -ne $container.name) {
            Set-SeApiContainer -CId $container.id -Name $newName -AuthToken $authtoken | Out-Null
            Write-Host "Renamed Sensorhub '$($container.name)' to '$newName'"
        }
    }
}
Write-Host "Finished renaming sensorhubs" -ForegroundColor Green