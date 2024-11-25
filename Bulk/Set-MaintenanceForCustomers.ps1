<#
.SYNOPSIS
Enable or disable maintenance mode for multiple customers

.DESCRIPTION
This script can be used to enable or disable maintenance mode for multiple customers at once.
If you want to enable maintenance mode, you have to provide a duration in hours.
If you want to disable maintenance mode, use the -Disable switch.
The script expects a list of customer objects as input, which can be retrieved using the Get-SECustomer cmdlet.
NOTE: This script requires an ApiKey to authenticate with the servereye API.

.PARAMETER CustomerId
The ID of the customer for which maintenance mode should be enabled or disabled.
This parameter is mandatory and should be provided by the pipeline.

.PARAMETER Duration
The duration in hours for which maintenance mode should be enabled.

.PARAMETER Disable
Use this switch to disable maintenance mode for the specified customers instead of enabling it.

.PARAMETER ApiKey
The users ApiKey to authenticate with the servereye API.

.EXAMPLE
Enable maintenance mode for all customers for 2 hours
Get-SECustomer | .\Set-MaintenanceForCustomers.ps1 -ApiKey "ApiKey" -Duration 2

.EXAMPLE
Disable maintenance mode for all customers
Get-SECustomer | .\Set-MaintenanceForCustomers.ps1 -ApiKey "ApiKey" -Disable

.NOTES
Author  : servereye
Version : 1.0
#>

[CmdletBinding()]
Param
( 
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
    [string]$CustomerId,
    [Parameter(Mandatory = $false)]
    [int]$Duration,
    [Parameter(Mandatory = $false)]
    [switch]$Disable,
    [Parameter(Mandatory = $true)]
    [Alias("AuthToken")]
    [string]$ApiKey
)

Begin {
    if (-not $Disable -and -not $Duration) {
        Write-Host "Please provide a duration or use the -Disable switch" -ForegroundColor Red
        Exit
    }
    if (-not $Disable -and $Duration -le 0) {
        Write-Host "Duration must be greater than 0" -ForegroundColor Red
        Exit
    }
    $headers = @{
        "x-api-key" = "$ApiKey"
    }
    $body = @{
        duration = "$Duration"
    } | ConvertTo-Json
}

Process {
    if (-not $Disable) {
        try {
            Invoke-RestMethod -Method 'Post' -Uri "https://api.server-eye.de/3/customer/$CustomerId/maintenance/enable" -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
            Write-Host "Maintenance mode has been enabled for customer '$($input.Name)'"
        }
        catch {
            Write-Host "Maintenance mode is already enabled for customer '$($input.Name)'" -ForegroundColor Yellow
        }
    } else {
        try {
            Invoke-RestMethod -Method 'Post' -Uri "https://api.server-eye.de/3/customer/$CustomerId/maintenance/disable" -Headers $headers -ContentType "application/json" | Out-Null
            Write-Host "Maintenance mode has been disabled for customer '$($input.Name)'"
        }
        catch {
            Write-Host "Maintenance mode is already disabled for customer '$($input.Name)'" -ForegroundColor Yellow
        }
    }
}

End {
    Write-Host "Done, maintenance mode has been set for all customers" -ForegroundColor Green
}