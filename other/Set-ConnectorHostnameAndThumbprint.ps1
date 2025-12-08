#Requires -RunAsAdministrator
<#
	.SYNOPSIS
	Sets the connector URL and SSL thumbprint for a Sensorhub.

	.DESCRIPTION
	This script updates the Sensorhub configuration file with the provided OCC-Connector hostname and SSL thumbprint,
	so that theres always a direct connection to the OCC-Connector without searching via UPNP.
	Optionally, you can remove existing entries.

	.PARAMETER ConnectorHostname
	The hostname of the OCC-Connector to connect to.

	.PARAMETER ConnectorSslThumbprint
	The SSL thumbprint of the OCC-Connector to connect to.

	.PARAMETER RemoveEntries
	Optional. If provided, removes connectorUrl and connectorSslThumbprint entries.

	.EXAMPLE
	PS> .\Set-ConnectorHostnameAndThumbprint.ps1 -ConnectorHostname "HV01" -ConnectorSslThumbprint "ABCDEF1234567890ABCDEF1234567890ABCDEF12"
	Sets the connector URL and SSL thumbprint in the Sensorhub configuration file.

	.EXAMPLE
	PS> .\Set-ConnectorHostnameAndThumbprint.ps1 -RemoveEntries "true"
	Removes existing connectorUrl and connectorSslThumbprint entries from the Sensorhub configuration file.

	.NOTES
	Author  : servereye
	Version : 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]
    $ConnectorHostname,

    [Parameter(Mandatory = $false)]
    [string]
    $ConnectorSslThumbprint,

	[Parameter(Mandatory = $false)]
    [string]
    $RemoveEntries
)

#region Variables
# servereye install path
if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    $SEInstPath = "$env:ProgramFiles\Server-Eye"
} else {
    $SEInstPath = "${env:ProgramFiles(x86)}\Server-Eye"
}

$CCConfigPath = "$SEInstPath\config\se3_cc.conf"

$LogPath = "$env:windir\Temp\Set-ConnectorHostnameAndThumbprint.log"
#endregion

#region Functions
function Log {
	Param (
		[Parameter(Mandatory=$true, Position=0)]
		[string]
		$LogMessage,

		[Parameter(Mandatory=$false)]
		[string]
		$LogPath = $LogPath,

		[Parameter(Mandatory=$false)]
		[switch]
		$ToScreen = $false,

		[Parameter(Mandatory=$false)]
		[switch]
		$ToFile = $false,

		[Parameter(Mandatory=$false)]
		[string]
		$ForegroundColor = "Gray",

		[Parameter(Mandatory=$false)]
		[string]
		$BackgroundColor = "Black"
	)

    $Stamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
    $LogMessage = "[$Stamp] $LogMessage"
	if ($ToScreen) {
    	Write-Host -Object $LogMessage -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
	}
	if ($ToFile) {
    	Add-Content -Path $LogPath -Value $LogMessage
	}
}
#endregion

#region Main execution
try {
	Log "Stopping servereye services..." -ToScreen -ToFile
	Stop-Service -Name "SE3Recovery" -ErrorAction Stop
	Stop-Service -Name "CCService" -ErrorAction Stop
	Log "Successfully stopped servereye services." -ToScreen -ToFile
}
catch {
	Log "Could not stop servereye services. Please stop them manually and execute the script again. Error:`n$_" -ToScreen -ToFile -ForegroundColor Red
	exit
}

try {
	Log "Reading CC config file at '$CCConfigPath'..." -ToScreen -ToFile
	$CCConfigLines = Get-Content -Path $CCConfigPath -ErrorAction Stop
	Log "Successfully read CC config file at '$CCConfigPath'." -ToScreen -ToFile
}
catch {
	Log "Could not read CC config file at '$CCConfigPath'. Stopping script execution. Error:`n$_" -ToScreen -ToFile -ForegroundColor Red
	exit
}

$urlFound = $false
$thumbFound = $false
for ($i = 0; $i -lt $CCConfigLines.Count; $i++) {
	if ($CCConfigLines[$i] -match '^connectorUrl=.*') {
		if ($RemoveEntries) {
			$CCConfigLines[$i] = ""
		} else {
			$CCConfigLines[$i] = "connectorUrl=https://$($ConnectorHostname):11000"
		}
		$urlFound = $true
	}
	if ($CCConfigLines[$i] -match '^connectorSslThumbprint=.*') {
		if ($RemoveEntries) {
			$CCConfigLines[$i] = ""
		} else {
			$CCConfigLines[$i] = "connectorSslThumbprint=$ConnectorSslThumbprint"
		}
		$thumbFound = $true
	}
}

if ((-not $urlFound) -and (-not $RemoveEntries)) {
	$CCConfigLines += "connectorUrl=https://$($ConnectorHostname):11000"
}
if ((-not $thumbFound) -and (-not $RemoveEntries)) {
	$CCConfigLines += "connectorSslThumbprint=$ConnectorSslThumbprint"
}

try {
	Log "Writing changes to CC config file at '$CCConfigPath'..." -ToScreen -ToFile
	Set-Content -Path $CCConfigPath -Value $CCConfigLines -ErrorAction Stop -Force
	Log "Successfully wrote changes to config file at '$CCConfigPath'." -ToScreen -ToFile
}
catch {
	Log "Could not write changes to CC config file at '$CCConfigPath'. Stopping script execution. Error:`n$_" -ToScreen -ToFile -ForegroundColor Red
	exit
}

try {
	Log "Starting servereye services..." -ToScreen -ToFile
	Start-Service -Name "CCService" -ErrorAction Stop
	Start-Service -Name "SE3Recovery" -ErrorAction Stop
	Log "Successfully started servereye services." -ToScreen -ToFile
}
catch {
	Log "Could not start servereye services. Please start them manually. Error:`n$_" -ToScreen -ToFile -ForegroundColor Red
	exit
}

Log "All done!" -ToScreen -ToFile -ForegroundColor Green
#endregion