#Requires -RunAsAdministrator
<#
    .SYNOPSIS
    Update Edge and Chrome browsers to latest version
 
    .DESCRIPTION
    The script forces an update of the Chrome and Edge browsers

    .PARAMETER Chrome
    If set, the script will check if Chrome is installed and update it

    .PARAMETER Edge
    If set, the script will check if Edge is installed and update it
       
    .NOTES
    Author  : Krämer IT Solutions GmbH / servereye
    Version : 1.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]
    $Chrome,
    [Parameter(Mandatory = $false)]
    [string]
    $Edge
)

if (Test-Path "$env:SystemDrive\ProgramData\ServerEye3\logs") {
    $LogPath = "$env:SystemDrive\ProgramData\ServerEye3\logs\Update-ChromeAndEdge.log"
} else {
    $LogPath = "$env:windir\Temp\Update-ChromeAndEdge.log"
}

function Log {
    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "[$Stamp] $LogString"
    Add-Content "$LogPath" -Value $LogMessage -ErrorAction Stop
}

$IsChromeInstalled = (Get-Item (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe")."(Default)").VersionInfo
$IsEdgeInstalled = Get-ItemProperty "HKLM:SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Select-Object DisplayName | Where-Object { $_.DisplayName -like "*Edge*" }

Log "Starting Update-ChromeAndEdge script..."
if ($Chrome) {
    Log "Checking if Chrome is installed..."
    if ($IsChromeInstalled) {
        Log "Chrome is installed. Looking for registry key..."
        if (Test-Path "HKLM:\SOFTWARE\Policies\Google\Update") {
            try {
                Log "Registry Key exists, setting registry values..."
                Set-Itemproperty -path "HKLM:\SOFTWARE\Policies\Google\Update" -Name "AutoUpdateCheckPeriodMinutes" -value "1" -ErrorAction Stop
                Set-Itemproperty -path "HKLM:\SOFTWARE\Policies\Google\Update" -Name "UpdateDefault" -value "1" -ErrorAction Stop
            } catch {
                Log "Error setting registry keys. Error: $_"
                Exit
            }
        }
        Log "Registry values set."
        $Path = (Get-Item $env:temp).FullName
        $Installer = "chrome_installer.exe"
        try {
            Log "Downloading Chrome installer..."
            $ProgressPreference = "SilentlyContinue"
            Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $Path\$Installer -ErrorAction Stop
            Log "Chrome installer downloaded successfully."
        } catch {
            Log "Error downloading Chrome installer. Error: $_"
            Exit
        }

        try {
            Log "Starting Chrome installer..."
            Start-Process -FilePath "$Path\$Installer" -Args "/silent /install" -Verb RunAs -Wait -ErrorAction Stop
            Log "Chrome installed successfully."
        } catch {
            Log "Error starting Chrome installer. Error: $_"
            Exit
        }

        try {
            Log "Removing Chrome installer..."
            Remove-Item "$Path\$Installer" -ErrorAction Stop
            Log "Chrome installer removed."
        } catch {
            Log "Error removing Chrome installer. Error: $_"
            Exit
        }
    } else {
        Log "Chrome is not installed."
    }
}

if ($Edge) {
    if ($IsEdgeInstalled) {
        try {
            $EdgeUpdaterPathx86 = "$env:SystemDrive\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"
            $EdgeUpdaterPathx64 = "$env:SystemDrive\Program Files\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"
            Log "Starting Edge Updater..."
            if (Test-Path $EdgeUpdaterPathx86) {
                Start-Process -FilePath $EdgeUpdatePathx86 `
                -argumentlist "/silent /install appguid={56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}&appname=Microsoft%20Edge&needsadmin=True" -ErrorAction Stop
            } elseif (Test-Path $EdgeUpdaterPathx64) {
                Start-Process -FilePath $EdgeUpdatePathx64 `
                -argumentlist "/silent /install appguid={56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}&appname=Microsoft%20Edge&needsadmin=True" -ErrorAction Stop
            } else {
                Log "Edge Updater path not found. Exiting..."
                Exit
            }
            Log "Edge Updater finished successfully."
        } catch {
            Log "Error starting Edge installer. Error: $_"
            Exit
        }
        
        try {
            Log "Setting Edge registry values..."
            Set-Itemproperty -path "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" -Name "UpdateDefault" -value "1" -ErrorAction Stop
            Log "Edge registry values set."
        } catch {
            Log "Error setting Edge registry values. Error: $_"
            Exit
        }
        try {
            Log "Starting Edge Updater for the second run..."
            Start-Process -FilePath "C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe" `
            -argumentlist "/silent /install appguid={56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}&appname=Microsoft%20Edge&needsadmin=True" -ErrorAction Stop
            Log "Edge Updater finished successfully."
        } catch {
            Log "Error starting Edge installer. Error: $_"
            Exit
        }
    } else {
        Log "Edge is not installed."
    }
}
Log "Finished Update-ChromeAndEdge script."