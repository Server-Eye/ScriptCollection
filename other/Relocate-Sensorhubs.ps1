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

    .PARAMETER deployAsSensorhub
    Pass "true" to deploy the system as a Sensorhub under the new OCC-Connector.
    This will delete se3_mac.conf and disable the OCC-Connector Service.

    .NOTES
    Author  : servereye
    Version : 1.1

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
    $cleanup,

    [Parameter(Mandatory = $false)]
    [string]
    $deployAsSensorhub
)

#region Internal variables
#servereye install path
if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    $SEInstPath = "$env:ProgramFiles\Server-Eye"
} else {
    $SEInstPath = "${env:ProgramFiles(x86)}\Server-Eye"
}

#servereye paths
$SEDataPath = "$env:ProgramData\ServerEye3"
$CCConfigPath = "$SEInstPath\config\se3_cc.conf"
$MACConfigPath = "$SEInstPath\config\se3_mac.conf"

#Is the system an OCC-Connector?
$OCCConnector = Test-Path "$SEInstPath\config\se3_mac.conf"

#Logfile path
$Logpath = "$SEinstPath\Relocate-Sensorhubs.log"
#endregion

#region Function declarations
function Log {
    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "[$Stamp] $LogString"
    Add-Content "$Logpath" -Value $LogMessage
}

function SECheck-ForServiceStop() {
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
}

function SEEdit-Configfile() {
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
    } else {
        Stop-Service "SE3Recovery", "CCService" -ErrorAction SilentlyContinue
    }
    SECheck-ForServiceStop
    if ($?) {Log "Stopped all services."}
    else {Log "Services are already stopped."}
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

function SEConvertTo-Sensorhub {
    Log "Disabling OCC-Connector service and deleting se3_mac.conf since -deployAsSensorhub was passed..."
    try {
        Set-Service "MACService" -StartupType Disabled -ErrorAction Stop
    }
    catch {
        Log "There was an issue disabling the OCC-Connector service:`n$_`nTerminating script."
        exit
    }
    try {
        Remove-Item -Path $MACConfigPath -Force -ErrorAction Stop
    }
    catch {
        Log "There was an issue deleting se3_mac.conf:`n$_`nTerminating script."
        exit
    }
}
#endregion

#region Main execution
SEStop-Services
if ($deployAsSensorhub -eq "true") { SEConvertTo-Sensorhub }
SEEdit-Configfile
SEClean-Datapath
SEStart-Services
#endregion