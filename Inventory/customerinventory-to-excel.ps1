#Requires -Modules ServerEye.Powershell.Helper, ImportExcel

<#
    .SYNOPSIS
    Export inventory data from all sensorhubs of one or more customers into an Excel file.

    .DESCRIPTION
    Reads all inventory data of all sensorhubs and exports it into an Excel file.
    Multiple customers can be passed via the pipeline (Get-SECustomer); in that case a single
    combined Excel file is created with a Customer column added to every worksheet.
    Requires: Install-Module -Name ServerEye.Powershell.Helper, ImportExcel

    .PARAMETER ApiKey
    The ApiKey of a user managing the customer(s).

    .PARAMETER CustomerID
    The ID of a single customer. Optional when customers are provided via the pipeline.

    .PARAMETER Dest
    Destination folder for the Excel file. A subfolder "inventory" will be created inside it.

    .PARAMETER InputCustomer
    Customer objects piped from Get-SECustomer. Multiple customers produce one combined Excel file.

    .NOTES
    Author  : Thomas Krammes of KITS, Modified by Patrick Hissler and Leon Zewe of servereye
    Version : 1.3

    .EXAMPLE
    # Single customer by ID
    .\customerinventory-to-excel.ps1 -ApiKey "your-key" -CustomerID "customer-id" -Dest "C:\Reports"

    .EXAMPLE
    # Multiple customers via pipeline — one combined Excel file
    Get-SECustomer -ApiKey "your-key" | .\customerinventory-to-excel.ps1 -ApiKey "your-key" -Dest "C:\Reports"

    .EXAMPLE
    # One file per customer using ForEach-Object
    Get-SECustomer -ApiKey "your-key" | ForEach-Object {
        .\customerinventory-to-excel.ps1 -ApiKey "your-key" -CustomerID $_.CustomerID -Dest "C:\Reports"
    }
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory)][string]$ApiKey,
    [Parameter()][string]$CustomerID,
    [Parameter(Mandatory)][string]$Dest,
    [Parameter(ValueFromPipeline)]$InputCustomer
)

begin {
    function Write-ProgressStatus {
        param (
            [string]$Activity,
            [int]$Counter,
            [int]$Max,
            [string]$Status,
            [int]$Id,
            [int]$ParentId = 0
        )

        $percent = if ($Max -gt 0) { [Math]::Min(($Counter * 100) / $Max, 100) } else { 100 }

        $params = @{
            Activity        = $Activity
            PercentComplete = $percent
            Status          = $Status
            Id              = $Id
        }
        if ($ParentId -gt 0) { $params['ParentId'] = $ParentId }

        Write-Progress @params
    }

    function Invoke-CustomerInventory {
    param (
        $Customer,
        [string]$XlsFile,
        [bool]$AddCustomerColumn = $false,
        [bool]$ClearExisting     = $true
    )

    $hubs      = Get-SeApiCustomerContainerList -AuthToken $ApiKey -CId $Customer.CId |
                     Where-Object Subtype -eq 2
    $hubCount  = $hubs.Count
    $hubIndex  = 0
    $initFile  = $ClearExisting
    $hostRows  = [System.Collections.Generic.List[object]]::new()
    $invObject = $null   # built lazily on the first hub that has inventory data

    foreach ($hub in $hubs) {
        $hubIndex++
        Write-ProgressStatus -Activity "Inventarisiere System: $hubIndex/$hubCount" `
            -Counter $hubIndex -Max $hubCount -Status $hub.Name -Id 2 -ParentId 1

        $hubDetail = Get-SeApiContainer -AuthToken $ApiKey -CId $hub.Id
        $state     = Get-SeApiContainerStateListbulk -AuthToken $ApiKey -CId $hub.Id
        $lastDate  = if ($null -eq $state.LastDate) { 'N/A' } else { [datetime]$state.LastDate }

        $hostRow = if ($AddCustomerColumn) {
            [PSCustomObject]@{
                Customer       = $Customer.CompanyName
                Hub            = $hub.Name
                MachineName    = $hubDetail.MachineName
                LastDate       = $lastDate
                Inventory      = $false
                OsName         = $hubDetail.OsName
                IsVM           = $hubDetail.IsVM
                IsServer       = $hubDetail.IsServer
                LastRebootUser = $hubDetail.LastRebootInfo.User
                CId            = $hub.Id
            }
        } else {
            [PSCustomObject]@{
                Hub            = $hub.Name
                MachineName    = $hubDetail.MachineName
                LastDate       = $lastDate
                Inventory      = $false
                OsName         = $hubDetail.OsName
                IsVM           = $hubDetail.IsVM
                IsServer       = $hubDetail.IsServer
                LastRebootUser = $hubDetail.LastRebootInfo.User
                CId            = $hub.Id
            }
        }

        # Skip hubs that are offline or have lost their connector connection
        $isOffline = ($lastDate -ne 'N/A' -and $lastDate -lt (Get-Date).AddDays(-60)) -or
                     $state.Message -eq 'OCC Connector hat die Verbindung zum Sensorhub verloren'
        if ($isOffline) {
            $hostRows.Add($hostRow)
            continue
        }

        # Fetch inventory with a 5-second timeout via a background job
        $inv = Start-Job -ScriptBlock {
            try { Get-SeApiContainerInventory -AuthToken $args[0] -CId $args[1] } catch { @() }
        } -ArgumentList $ApiKey, $hub.Id | Wait-Job -Timeout 5 | Receive-Job
        Get-Job | Remove-Job -Force

        if (-not $inv) {
            $hostRows.Add($hostRow)
            continue
        }

        $hostRow.Inventory = $true
        $hostRows.Add($hostRow)

        if (-not $invObject) {
            $invObject = [PSCustomObject]@{ Hosts = $null }
        }

        $categories = $inv | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

        foreach ($category in $categories) {
            if (-not $inv.$category) { continue }

            # Use RealHost column if present (it becomes the Host column), otherwise use Host
            $hasHost = $inv.$category | Get-Member -Name Host -MemberType NoteProperty -ErrorAction SilentlyContinue
            $rows = if ($hasHost) {
                $inv.$category | Select-Object RealHost, *
            } else {
                $inv.$category | Select-Object Host, *
            }

            foreach ($row in @($rows)) { $row.Host = $hub.Name }

            if ($AddCustomerColumn) {
                $rows = @($rows) | Select-Object @{ N='Customer'; E={ $Customer.CompanyName } }, *
            }

            # Delete a stale file on the very first write of this run
            if ($initFile -and (Test-Path $XlsFile)) {
                Export-Excel -Path $XlsFile -KillExcel
                Remove-Item $XlsFile
            }
            $initFile = $false

            if ($invObject.PSObject.Properties.Name -contains $category) {
                $invObject.$category += $rows
            } else {
                $invObject | Add-Member -NotePropertyName $category -NotePropertyValue @($rows)
            }
        }
    }

    if (-not $invObject) {
        $invObject = [PSCustomObject]@{ Hosts = $null }
    }
    $invObject.Hosts = $hostRows

    # Write every category as its own worksheet; shared Export-Excel parameters via splatting
    $categories = $invObject | Get-Member -MemberType NoteProperty |
                      Where-Object Name -ne 'Hosts' | Select-Object -ExpandProperty Name
    $sheetCount = $categories.Count + 1   # +1 for the Hosts sheet
    $sheetIndex = 0

    $xlParams = @{
        Path         = $XlsFile
        Append       = $true
        AutoFilter   = $true
        AutoSize     = $true
        FreezeTopRow = $true
        BoldTopRow   = $true
        KillExcel    = $true
    }

    $invObject.Hosts | Export-Excel @xlParams -WorksheetName 'Hosts'

    foreach ($category in $categories) {
        $sheetIndex++
        Write-ProgressStatus -Activity "$sheetIndex/$sheetCount Schreibe Excel: $(Split-Path $XlsFile -Leaf)" `
            -Counter $sheetIndex -Max $sheetCount -Status $category -Id 2 -ParentId 1
        $invObject.$category | Export-Excel @xlParams -WorksheetName $category -NoNumberConversion *
    }
}

    $pipedCustomers = [System.Collections.Generic.List[object]]::new()
}

process {
    if ($InputCustomer) { $pipedCustomers.Add($InputCustomer) }
}

end {
    # Resolve the list of customers to process
    if ($pipedCustomers.Count -gt 0) {
        # Normalise piped objects — Get-SECustomer returns CId + CompanyName
        $customers = $pipedCustomers | ForEach-Object {
            $cid  = if ($_.PSObject.Properties['CId'])           { $_.CId }
                    elseif ($_.PSObject.Properties['CustomerId']) { $_.CustomerId }
                    else                                          { $_.CustomerID }
            $name = if ($_.PSObject.Properties['CompanyName'])   { $_.CompanyName }
                    elseif ($_.PSObject.Properties['Name'])       { $_.Name }
                    else                                          { 'Unknown' }
            if ($cid) { [PSCustomObject]@{ CId = $cid; CompanyName = $name } }
        } | Where-Object { $_ }
    } elseif ($CustomerID) {
        try   { $customers = @(Get-SeApiCustomerlist -AuthToken $ApiKey | Where-Object CId -eq $CustomerID) }
        catch { Write-Host 'ApiKey falsch'; return }
        if (-not $customers) { Write-Host 'Customer nicht gefunden'; return }
    } else {
        try   { $customers = Get-SeApiCustomerlist -AuthToken $ApiKey }
        catch { Write-Host 'ApiKey falsch'; return }
    }

    if (-not (Test-Path $Dest)) {
        New-Item -Path $Dest -ItemType Directory | Out-Null
    }

    $inventoryRoot = Join-Path $Dest 'inventory'
    if (-not (Test-Path $inventoryRoot)) {
        New-Item -Path $inventoryRoot -ItemType Directory | Out-Null
    }

    # One file per customer, or one combined file for multiple customers
    $multiCustomer = $customers.Count -gt 1
    $xlsFile = if ($multiCustomer) {
        Join-Path $inventoryRoot "MultiCustomer_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
    } else {
        $safeName = $customers[0].CompanyName -replace '[<>:"/\\|?*]', '_'
        Join-Path $inventoryRoot "$safeName.xlsx"
    }

    # Clear any existing combined file before starting so we don't append to stale data
    if ($multiCustomer -and (Test-Path $xlsFile)) {
        Export-Excel -Path $xlsFile -KillExcel
        Remove-Item $xlsFile
    }

    $customerCount = $customers.Count
    $customerIndex = 0

    foreach ($customer in $customers) {
        $customerIndex++
        Write-Host $customer.CompanyName
        Write-ProgressStatus -Activity "Inventarisiere Kunde: $customerIndex/$customerCount" `
            -Counter $customerIndex -Max $customerCount -Status $customer.CompanyName -Id 1

        Invoke-CustomerInventory -Customer $customer -XlsFile $xlsFile `
            -AddCustomerColumn $multiCustomer -ClearExisting (-not $multiCustomer)
    }
}
