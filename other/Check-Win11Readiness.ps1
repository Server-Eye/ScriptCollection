<#
.SYNOPSIS
Check if the system is Windows 11 ready and set a tag on the Sensorhub accordingly. Optionally export the results to an Excel file.

.DESCRIPTION
If you pass the argument -DoCheck, the script checks if the system is Windows 11 ready and sets a tag on the Sensorhub accordingly.
The script uses the ServerEye.Powershell.Helper module to authenticate with the Server-Eye API and retrieve the Sensorhub GUID. 
It then downloads the hardware readiness script from Microsoft, executes it, and sets the appropriate tag based on the result.
When the -DoExcelExport parameter is used, the script will export the results to an Excel file. This parameter should only be used locally on your system.

Note: The script requires an authtoken (apikey) as a parameter to connect to the servereye API.

.PARAMETER AuthToken
The authtoken (apikey) to connect to the servereye API.

.PARAMETER DoCheck
If you set this to "true", the script will check if the system is Windows 11 ready and set a tag on the Sensorhub accordingly.

.PARAMETER DoExcelExport
This parameter should only be used when executing the script locally on your system.
If you set this to "true", the script will export a list of all systems with either the Win11Ready or NotWin11Ready tags to an Excel file.

.PARAMETER Path
The path where the Excel file should be saved. If not set, the file will be opened in Excel and has to be saved manually.

.NOTES
Author  : servereye
Version : 1.1
#>

Param(
    [Parameter(Mandatory = $true)]
    [Alias("ApiKey")]
    [string]
    $AuthToken,
    [Parameter(Mandatory = $false)]
    [string]
    $DoCheck,
    [Parameter(Mandatory = $false)]
    [string]
    $DoExcelExport,
    [Parameter(Mandatory = $false)]
    [string]
    $Path
)

$LogPath = "$env:ProgramData\ServerEye3\logs\Check-Win11Readiness.log"
function Log {
    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "[$Stamp] $LogString"
    Add-Content "$LogPath" -Value $LogMessage
}

# Get servereye install path
if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    $SEInstPath = "$env:ProgramFiles\Server-Eye"
} else {
    $SEInstPath = "${env:ProgramFiles(x86)}\Server-Eye"
}

# Set se3_cc.conf path
$configPath = "$SEInstPath\config\se3_cc.conf"

Log "Starting Check-Win11Readiness script"

# Install and import servereye helper module and excel module
try {
    Log "Installing and importing needed modules"
    Install-PackageProvider -Name NuGet -Confirm:$false -Force -ErrorAction SilentlyContinue
    if (-not (Get-InstalledModule -Name "ServerEye.Powershell.Helper")) {
        Install-Module -Name ServerEye.Powershell.Helper -Confirm:$false -Force -ErrorAction Stop
        Import-Module -Name ServerEye.Powershell.Helper -Force -ErrorAction Stop
        Log "Imported ServerEye.Powershell.Helper module"
    } else {
        Log "ServerEye.Powershell.Helper module is already installed"
    }
    if (-not (Get-InstalledModule -Name "ImportExcel")) {
        Install-Module -Name ImportExcel -Confirm:$false -Force -ErrorAction Stop
        Import-Module -Name ImportExcel -Force -ErrorAction Stop
        Log "Imported ImportExcel module"
    } else {
        Log "ImportExcel module is already installed"
    }
} catch {
    Log "Failed to install or import needed modules. Error: $_"
    exit
}

# Get authtoken via API-Key
try {
    Log "Authenticating with servereye API"
    $AuthToken = Connect-SESession -Apikey $AuthToken -ErrorAction Stop
} catch {
    Log "Failed to authenticate with servereye API. Error: $_"
    exit
}

if ($DoCheck) {
    # Get guid of Sensorhub from se3_cc.conf so we can set the tag later
    try {
        Log "Getting Sensorhub GUID from se3_cc.conf"
        $guid = (Get-Content $configPath -ErrorAction Stop | Where-Object {$_ -Like "guid=*"}).Split("=")[-1]
    } catch {
        Log "Failed to get Sensorhub GUID from se3_cc.conf. Error: $_"
        exit
    }

    # Get tags of Sensorhub
    try {
        Log "Getting Tags of Sensorhub"
        $TagsOnSensorhub = (Get-SESensorhubtag -SensorhubId $guid -ErrorAction Stop).Tag
    } catch {
        Log "Failed to get Tags of Sensorhub. Error: $_"
        exit
    }

    # Make sure that we don't set the tag twice if the script has been executed on this system before
    if ($TagsOnSensorhub -match "Win11Ready" -or $TagsOnSensorhub -match "NotWin11Ready") {
        Log "Tag already exists on the Sensorhub, nothing needs to be done here. Exiting."
        exit
    }

    # Check if the tags Win11Ready and NotWin11Ready exist, if not, exit the script
    try {
        Log "Checking if Tags exist"
        $Tags = Get-SETag -AuthToken $AuthToken
        $Win11ReadyTag = $Tags | Where-Object Name -eq "Win11Ready"
        $NotWin11ReadyTag = $Tags | Where-Object Name -eq "NotWin11Ready"
        switch ($true) {
            { $Win11ReadyTag -and $NotWin11ReadyTag } {
                Log "Both 'Win11Ready' and 'NotWin11Ready' tags exist, continuing."
            }
            { -not $Win11ReadyTag -and -not $NotWin11ReadyTag } {
                Log "Both 'Win11Ready' and 'NotWin11Ready' tags do not exist, please create them in the OCC. Exiting."
                exit
            }
            { -not $Win11ReadyTag } {
                Log "'Win11Ready' tag does not exist, please create it in the OCC. Exiting."
                exit
            }
            { -not $NotWin11ReadyTag } {
                Log "'NotWin11Ready' tag does not exist, please create it in the OCC. Exiting."
                exit
            }
            { $Win11ReadyTag.Count -gt 1 -or $NotWin11ReadyTag.Count -gt 1 } {
                Log "More than one 'Win11Ready' or 'NotWin11Ready' tag exists, please correct this in the OCC. Exiting."
                exit
            }
        }
    } catch {
        Log "Failed to check for existance of Tags. Error: $_"
        exit
    }

    # Download hardware readiness script and execute it, remove script after we get the result
    try {
        Log "Downloading and executing hardware readiness script"
        Invoke-WebRequest -Uri "https://aka.ms/HWReadinessScript" -Outfile "$env:TEMP\HWReadinessScript.ps1" -ErrorAction Stop
        $result = . "$env:TEMP\HWReadinessScript.ps1" -ErrorAction Stop
        Remove-Item "$env:TEMP\HWReadinessScript.ps1" -Force -ErrorAction Stop
    } catch {
        Log "Failed to download, execute or delete hardware readiness script. Error: $_"
        exit
    }

    # Set tag based on result. As per Microsoft documentation, returnCode:0 means Win11 ready, anything else means not ready
    try {
        Log "Setting Tag based on result"
        if ($result -match '"returnCode":0') {
            Set-SETag -AuthToken $AuthToken -SensorhubId $guid -TagId (Get-SETag -AuthToken $AuthToken | Where-Object Name -eq "Win11Ready").TagID
            Log "Set Tag 'Win11Ready' on Sensorhub"
        } else {
            Set-SETag -AuthToken $AuthToken -SensorhubId $guid -TagId (Get-SETag -AuthToken $AuthToken | Where-Object Name -eq "NotWin11Ready").TagID
            Log "Set Tag 'NotWin11Ready' on Sensorhub"
        }
    } catch {
        Log "Failed to set Tag. Error: $_"
        exit
    }
}

if ($DoExcelExport) {
    # Get all customers and their containers, to check which Sensorhubs have one of the tags set
    $Containers = Get-SeApiCustomerList -ApiKey $AuthToken | ForEach-Object {Get-SeApiCustomerContainerList -CId $_.cId -ApiKey $AuthToken}
    $Win11ReadyContainers = $Containers | Where-Object { $_.tags -match "name=Win11Ready" }
    $NotWin11ReadyContainers = $Containers | Where-Object { $_.tags -match "name=NotWin11Ready" }

    # Build the objects for the Excel export
    $Result = @()

    $Win11ReadyContainers | ForEach-Object {
        $Result += [PSCustomObject]@{
            Customer = (Get-SeApiCustomer -CId $_.customerId -ApiKey $AuthToken).companyName
            Sensorhub = $_.name
            Windows11Ready = "Yes"
        }
    }

    $NotWin11ReadyContainers | ForEach-Object {
        $Result += [PSCustomObject]@{
            Customer = (Get-SeApiCustomer -CId $_.customerId -ApiKey $AuthToken).companyName
            Sensorhub = $_.name
            Windows11Ready = "No"
        }
    }

    # Export the results to an Excel file
    if ($Path) {
        $Result | Export-Excel -Path $Path -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -WorksheetName "Win11Readiness"
    } else {
        $Result | Export-Excel -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -WorksheetName "Win11Readiness"
    }
}

Log "Finished Check-Win11Readiness script"