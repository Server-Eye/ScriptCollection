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
	
	 
$CustomerListe = [System.Collections.ArrayList]@()

	 foreach( $customer in Get-SECustomer) {
	        
            $name = $customer.Name
            $clientCount =0
            $serverCount =0

		foreach($sensorhub in Get-SESensorhub -CustomerId $customer.CustomerId){
            
            

            if($sensorhub.IsServer){
            $serverCount++
            }else{
            $clientCount++
            }

		

	}
    
        $CustomerObj = [PSCustomObject]@{
    Name = "Customer"
    clientCount = 0
    serverCount = 0
}
	    $CustomerObj.Name = $name
        $CustomerObj.clientCount = $clientCount
        $CustomerObj.serverCount = $serverCount

        Write-Host "Customer: " $CustomerObj.Name  " Clientsensoren:  "$CustomerObj.clientCount " ServerSensoren: "$CustomerObj.serverCount

        $CustomerListe.Add($CustomerObj)

	 }
	 
$ExcelDatei =  $excelPath+"\Liste.xls"
	 

$CustomerListe | Export-Excel -Path $ExcelDatei -AutoSize