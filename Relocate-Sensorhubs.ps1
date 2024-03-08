#Requires -RunAsAdministrator
<#
    .SYNOPSIS
    Relocate Sensorhub to new customer and OCC-Connector
    
    .DESCRIPTION
    Relocates a Sensorhub by modifying se3_cc.conf in the servereye directory.
    First, the servereye services are stopped. Then the contents of se3_cc.conf are read and the lines customerID, parentGUID
    and secretKey are replaced. Afterwards the services are started again, and depending on if the user passed the cleanup
    argument, the folder ServerEye3 in ProgramData is deleted recursively.

    .PARAMETER customerID
    customer ID of the customer where the system should be relocated.

    .PARAMETER parentGuid
    container ID of the OCC-Connector where the Sensorhub should be relocated.

    .PARAMETER secretKey
    secretKey of the customer where the system should be relocated.

    .PARAMETER cleanup
    Pass "true" to delete the ServerEye3 folder in ProgramData.

    .NOTES
    Author  : servereye
    Version : 1.0

    .EXAMPLE
    PS C:\> .\Relocate-Sensorhubs.ps1 -customerID 42569786 -parentGuid 4f1kg420-2315-28he-89bc-509s20b25f76 -secretkey 
    e12ejgcf-d491-9892-bg83-95ka457938c2 -cleanup true

    Replaces the specified entries and deletes ServerEye3 folder in Programdata.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [string]
    $customerID,

    [Parameter(Mandatory = $true)]
    [string]
    $parentGuid,

    [Parameter(Mandatory = $true)]
    [string]
    $secretKey,
            
    [Parameter(Mandatory = $false)]
    [string]
    $cleanup
)

#region Internal variables
#servereye install path
if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    $SEInstPath = "$env:ProgramFiles\Server-Eye"
} else {
    $SEInstPath = "${env:ProgramFiles(x86)}\Server-Eye"
}

#servereye data path
$SEDataPath = "$env:ProgramData\ServerEye3"

#Is the system an OCC-Connector?
$OCCConnector = Test-Path "$SEInstPath\config\se3_mac.conf"

#Logfile path
$Logpath = "$SEDataPath\logs\Relocate-Sensorhubs.log"
#endregion

#region Function declarations
function Log {
    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "[$Stamp] $LogString"
    Add-Content "$Logpath" -Value $LogMessage
}

function SEEdit-Configfile() {
    $CCConfigPath = "$SEInstPath\config\se3_cc.conf"
    $customerString = "customer="
    $parentGuidString = "parentGuid="
    $secretKeyString = "secretKey="
    $guidString = "guid="
    Log "Modifying se3_cc.conf..."
    try {
        $content = Get-Content "$CCConfigPath" -Raw -ErrorAction Stop
        #Regex magic, replaces each line with the desired string
        $content = $content -replace "$customerString.*", "customer=$customerID"
        $content = $content -replace "$parentGuidString.*", "parentGuid=$parentGuid"
        $content = $content -replace "$secretKeyString.*", "secretKey=$secretKey"
        $content = $content -replace "\n$guidString.*", "`nguid="
        $content | Set-Content $CCConfigPath
        Log "Successfully modified se3_cc.conf."
    }
    catch {
        Log "There was an issue modifying se3_cc.conf:`n$_`nTerminating script."
        exit
    }
}

function SEStop-Services() {
    Log "Making sure all servereye services are stopped..."
    if ($OCCConnector) {
        Stop-Service "SE3Recovery", "CCService", "MACService" -ErrorAction SilentlyContinue
        $SECCService = Get-Service -Name CCService
        $SEMACService = Get-Service -Name MACService
        $SERecovery = Get-Service -Name SE3Recovery
        for ($i = 0; $i -le 20; $i++) {
            $SECCService = Get-Service -Name CCService
            $SEMACService = Get-Service -Name MACService
            $SERecovery = Get-Service -Name SE3Recovery
        
            if ($SECCService.Status -eq "Stopped" -and $SEMACService.Status -eq "Stopped" -and $SERecovery.Status -eq "Stopped") {
                break
            }
        
            Start-Sleep -Seconds 3
        }
        if ($?) {Log "Stopped all services."}
        else {Log "Services are already stopped."}
    } else {
        Stop-Service "SE3Recovery", "CCService" -ErrorAction SilentlyContinue
        $SECCService = Get-Service -Name CCService
        $SEMACService = Get-Service -Name MACService
        $SERecovery = Get-Service -Name SE3Recovery
        while ($SECCService.Status -ne "Stopped" -or $SEMACService.Status -ne "Stopped" -or $SERecovery.Status -ne "Stopped") {
            Start-Sleep -Seconds 3
            $SECCService = Get-Service -Name CCService
            $SEMACService = Get-Service -Name MACService
            $SERecovery = Get-Service -Name SE3Recovery
            $i++
            if ($i -gt 20) {
                Log "The servereye services couldn't be stopped within 60 seconds, exiting."
                exit
            }
        }
        if ($?) {Log "Stopped all services."}
        else {Log "Services are already stopped."}
    }
}

function SEStart-Services() {
    try {
        Log "Starting the needed services..."
        if ($OCCConnector) {
            Start-Service "SE3Recovery", "CCService", "MACService" -ErrorAction Stop
        } else {
            Start-Service "SE3Recovery", "CCService" -ErrorAction Stop
        }
        Log "Started all needed services."
    }
    catch {
        Log "There was an issue starting the services:`n$_`nTerminating script."
        exit
    }
}

function SEClean-Datapath() {
    if ($cleanup -eq "true") {
        Remove-Item -Recurse -Force $SEDataPath
    }
}
#endregion

#region Main execution
SEStop-Services
SEEdit-Configfile
SEClean-Datapath
SEStart-Services
#endregion