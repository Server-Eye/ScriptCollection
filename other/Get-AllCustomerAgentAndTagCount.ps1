#Requires -Module Powershell.Helper
#Requires -Module ImportExcel
<#
    .SYNOPSIS
        Collects system data and generates an Excel report with Client/Server counts and tags for each customer.
        
    .DESCRIPTION
        This script retrieves all system data, groups systems by their parent customer, and counts how many Clients and Servers are associated with each customer. 
        It also collects all tags related to the systems and displays the count of each tag for each customer. 
        The result is an Excel file that contains one row per customer, with dynamic columns for each tag, as well as counts for Clients and Servers.
        
    .PARAMETER ApiKey 
        The API key for authentication with the SE API.
        
    .PARAMETER excelPath 
        The directory path where the generated Excel file will be saved.
        
    .NOTES
        Author  : servereye
        Version : 1.0
        Updated : 2025-04-09
        Purpose : To provide an overview of system counts and tags for each customer

    .EXAMPLE
        PS C:\> .\Get-AllCustomerAgentAndTagCount.ps1 -ApiKey "your_api_key_here" -excelPath "C:\Path\To\Save\Report"
  
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]
    [alias("ApiKey", "Session")]
    $AuthToken,

    [Parameter(Mandatory = $true)]
    $excelPath
)

Install-Module -Name ServerEye.Powershell.Helper
Import-Module -Name ServerEye.Powershell.Helper
Import-Module ImportExcel

$msg = new-object System.Text.StringBuilder
$exitCode = 0

if ($authtoken -is [string]) {
    Connect-SESession -Apikey $authtoken
} else {
    Connect-SESession -WebSession $authtoken
}

$rawObjects = Get-SEApiMyNodesList -AuthToken $authtoken -Filter agent,container,customer
$customers = $rawObjects | Where-Object { $_.type -eq 1 }

$allTagNames = @()
foreach ($obj in $rawObjects) {
    if ($obj.PSObject.Properties['tags']) {
        foreach ($tag in $obj.tags) {
            if (-not $allTagNames.Contains($tag.name)) {
                $allTagNames += $tag.name
            }
        }
    }
}
$allTagNames = $allTagNames | Sort-Object

$output = @()

foreach ($customer in $customers) {
    $customerId = $customer.id
    $customerName = $customer.name
    $children = $rawObjects | Where-Object { $_.customerID -eq $customerId }

    $tagCount = @{}
    $clientCount = 0
    $serverCount = 0

    foreach ($child in $children) {
        if ($child.PSObject.Properties['tags']) {
            foreach ($tag in $child.tags) {
                $tagName = $tag.name
                if ($tagCount.ContainsKey($tagName)) {
                    $tagCount[$tagName] += 1
                } else {
                    $tagCount[$tagName] = 1
                }
            }
        }

        if ($child.subtype -eq 2) {
            if ($child.isServer) {
                $serverCount += 1
            } else {
                $clientCount += 1
            }
        }
    }

    $row = [ordered]@{}
    $row['ParentName'] = $customerName
    $row['ClientCount'] = $clientCount
    $row['ServerCount'] = $serverCount

    foreach ($tagName in $allTagNames) {
        $row[$tagName] = if ($tagCount.ContainsKey($tagName)) { $tagCount[$tagName] } else { 0 }
    }

    $output += [PSCustomObject]$row
}

$ExcelFile = $excelPath + "\Liste.xls"
$output | Export-Excel -Path $ExcelFile -AutoSize -BoldTopRow
