#Requires -RunAsAdministrator
	<#
	    .SYNOPSIS
	        Get all Client and Server Agents
	        
	    .DESCRIPTION
	         Get all Client and Server Agents
	    .PARAMETER ApiKey 
	    The apikey from the OCC.
	    .PARAMETER excelPath 
	    Path where the xls have to be saved.
	    .NOTES
	        Author  : Server-Eye
	        Version : 1.0
	    .Link
	    
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
      }
      else{
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

        if($child.subtype -eq 2){
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

$ExcelDatei = $excelPath + "\Liste.xls"
$output | Export-Excel -Path $ExcelDatei -AutoSize -BoldTopRow

