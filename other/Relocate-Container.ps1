#Requires -RunAsAdministrator
<#
    .SYNOPSIS
    Relocates a container (Sensorhub or OCC-Connector) to a new customer by modifying the configuration files in the servereye directory.
    
    .DESCRIPTION
    Relocates a Sensorhub or OCC-Connector by modifying the configuration files (se3_cc.conf and optionally se3_mac.conf) in the servereye directory.
    The script stops the servereye services, updates the configuration files with the provided CustomerNumber, ParentGuid, and SecretKey, and restarts the services.
    It also supports additional functionality such as moving agents (sensors) to the new container, copying container settings, removing the old container, and handling OCC-Connector-specific configurations.
    Depending on the parameters provided, the script can also convert a system between Sensorhub and OCC-Connector.

    .PARAMETER MoveAs
    Specifies whether the system should be relocated as a Sensorhub or an OCC-Connector. Valid values are "Sensorhub" or "OCC-Connector".

    .PARAMETER MoveSensors
    Indicates whether the agents (sensors) should also be moved to the new container. Pass "true" to move sensors, otherwise leave empty.

    .PARAMETER CopyContainerSettings
    Indicates whether the container settings should be copied from the old container(s) to the new one. Pass "true" to copy settings, otherwise leave empty.

    .PARAMETER RemoveContainer
    Indicates whether the old container should be removed after relocation. Pass "true" to remove the Sensorhub container, otherwise leave empty.

    .PARAMETER CustomerNumber
    CustomerNumber of the customer where the system should be relocated.

    .PARAMETER ParentGuid
    ContainerID of the OCC-Connector where the Sensorhub should be relocated. If the system is an OCC-Connector, or will be relocated as an OCC-Connector, this parameter is not required.

    .PARAMETER SecretKey
    SecretKey of the customer where the system should be relocated.

    .PARAMETER ApiKeyCurrentDistributor
    The API key of the current distributor. This is required to authenticate API calls for the current distributor.
    Note: You only need to provide this if you are using one of these parameters: MoveSensors, CopyContainerSettings, RemoveContainer

    .PARAMETER ApiKeyNewDistributor
    The API key of the new distributor. If not provided, the current distributor's API key will be used.
    This parameter doesn't need to be provided if the distributor stays the same.
    Note: You only need to provide this if you are using one of these parameters: MoveSensors, CopyContainerSettings, RemoveContainer

    .NOTES
    Author  : servereye
    Version : 1.3

    .EXAMPLE
    PS> .\Relocate-Container.ps1 -MoveAs 'Sensorhub' -CustomerNumber '42569786' -ParentGuid '4f1kg420-2315-28he-89bc-509s20b25f76' -SecretKey 'e12ejgcf-d491-9892-bg83-95ka457938c2'
    Relocates a container to the specified customer with the given parent GUID and secret key.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Sensorhub", "OCC-Connector")]
    [string]
    $MoveAs,

    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false")]
    [string]
    $MoveSensors,

    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false")]
    [string]
    $CopyContainerSettings,

    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false")]
    [string]
    $RemoveContainer,

    [Parameter(Mandatory = $true)]
    [string]
    $CustomerNumber,

    [Parameter(Mandatory = $false)]
    [string]
    $ParentGuid,

    [Parameter(Mandatory = $true)]
    [string]
    $SecretKey,

    [Parameter(Mandatory = $false)]
    [string]
    $ApiKeyCurrentDistributor,

    [Parameter(Mandatory = $false)]
    [string]
    $ApiKeyNewDistributor
)

#region Internal variables
# servereye install path
if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    $SEInstPath = "$env:ProgramFiles\Server-Eye"
} else {
    $SEInstPath = "${env:ProgramFiles(x86)}\Server-Eye"
}

# servereye paths
$SEDataPath = "$env:ProgramData\ServerEye3"
$CCConfigPath = "$SEInstPath\config\se3_cc.conf"
$MACConfigPath = "$SEInstPath\config\se3_mac.conf"

# Is the system an OCC-Connector?
$IsOCCConnector = Test-Path $MACConfigPath

# If no new distributor API-Key is passed, assume the distributor will stay the same and use the current API key
if (-not $ApiKeyNewDistributor) {
    $ApiKeyNewDistributor = $ApiKeyCurrentDistributor
} elseif (-not $ApiKeyCurrentDistributor) {
    $ApiKeyCurrentDistributor = $ApiKeyNewDistributor
}

# Get the current GUID(s)
$OldCCId = (Get-Content $CCConfigPath -ErrorAction Stop | Select-String -Pattern "^guid=").ToString().Split("=")[1].Trim()
if ($IsOCCConnector) {
    $OldMACId  = (Get-Content $MACConfigPath -ErrorAction Stop | Select-String -Pattern "^guid=").ToString().Split("=")[1].Trim()
}

#Logfile path
$Logpath = "$env:windir\Temp\Relocate-Container.log"
#endregion

#region Function declarations
function Log {
    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
    $LogMessage = "[$Stamp] $LogString"
    Add-Content "$Logpath" -Value $LogMessage
    Write-Host $LogMessage
}

function Test-SEServiceStop() {
    $SECCService = Get-Service -Name CCService
    $SEMACService = Get-Service -Name MACService
    $SERecovery = Get-Service -Name SE3Recovery
    for ($i = 0; $i -le 6; $i++) {
        if ($i -eq 6) {
            Log "Failed to stop all services after 60 seconds. Terminating script."
            exit
        }

        $SECCService = Get-Service -Name CCService
        $SEMACService = Get-Service -Name MACService
        $SERecovery = Get-Service -Name SE3Recovery
    
        if (($SECCService.Status -eq "Stopped") -and ($SEMACService.Status -eq "Stopped") -and ($SERecovery.Status -eq "Stopped")) {
            break
        }
    
        Start-Sleep -Seconds 10
    }    
}

function Edit-SEConfigFiles() {
    if (($IsOCCConnector) -and ($MoveAs -eq "OCC-Connector")) {
        try {
            Log "Modifying se3_mac.conf..."
            $content = Get-Content $MACConfigPath -Raw -ErrorAction Stop
            # Use multiline regex mode to replace each config line
            $content = [regex]::Replace($content, "^customer=.*$", "customer=$CustomerNumber", "Multiline")
            $content = [regex]::Replace($content, "^secretKey=.*$", "secretKey=$SecretKey", "Multiline")
            $content = [regex]::Replace($content, "^guid=.*$", "guid=", "Multiline")
            $content | Set-Content $MACConfigPath -NoNewline
            Log "Successfully modified se3_mac.conf."
        }
        catch {
            Log "There was an issue modifying se3_mac.conf:`n$_`nTerminating script."
            exit
        }
    }

    try {
        Log "Modifying se3_cc.conf..."
        $content = Get-Content $CCConfigPath -Raw -ErrorAction Stop
        # Use multiline regex mode to replace each config line
        $content = [regex]::Replace($content, "^customer=.*$", "customer=$CustomerNumber", "Multiline")
        $content = [regex]::Replace($content, "^parentGuid=.*$", "parentGuid=$ParentGuid", "Multiline")
        $content = [regex]::Replace($content, "^secretKey=.*$", "secretKey=$SecretKey", "Multiline")
        $content = [regex]::Replace($content, "^guid=.*$", "guid=", "Multiline")
        $content | Set-Content $CCConfigPath -NoNewline
        Log "Successfully modified se3_cc.conf."
    }
    catch {
        Log "There was an issue modifying se3_cc.conf:`n$_`nTerminating script."
        exit
    }
}

function Stop-SEServices() {
    Log "Making sure all servereye services are stopped..."
    if ($IsOCCConnector) {
        Stop-Service "SE3Recovery", "MACService", "CCService" -ErrorAction SilentlyContinue
    } else {
        Stop-Service "SE3Recovery", "CCService" -ErrorAction SilentlyContinue
    }
    Test-SEServiceStop
    if ($?) {Log "Stopped all services."}
    else {Log "Services are already stopped."}
}

function Start-SEServices() {
    try {
        if (($IsOCCConnector -or ($MoveAs -eq "OCC-Connector")) -and -not ($MoveAs -eq "Sensorhub")) {
            Log "Starting MACService and waiting for new OCC-Connector GUID..."
            Start-Service "MACService" -ErrorAction Stop
            Log "Started MACService."
            Log "Waiting for MACService to generate the new GUID..."
            for ($i = 1; $i -le 120; $i++) {
                Start-Sleep -Seconds 10
                $GuidLine = Get-Content $MACConfigPath -ErrorAction Stop | Select-String -Pattern "^guid="
                if ($null -ne $GuidLine) {
                    $Guid = $GuidLine.ToString().Split("=")[1].Trim()
                    if (-not [string]::IsNullOrWhiteSpace($Guid)) {
                        Log "New OCC-Connector GUID: $Guid"
                        break
                    }
                }
                Log "Attempt $($i): GUID is empty or not found, waiting 10 seconds..."
                if ($i -eq 120) {
                    Log "Failed to get new OCC-Connector GUID after 20 minutes, relocation has failed. Terminating script."
                    exit
                }
            }

            # Sleep for a bit to let MACService sort things out for itself, since CCService will grab the wrong parentGuid down the line if we don't.
            # This isn't pretty but so far we haven't found a proper check for this.
            Start-Sleep -Seconds 10

            Log "Starting CCService and SE3Recovery..."
            Start-Service "CCService", "SE3Recovery" -ErrorAction Stop
            Log "Started CCService and SE3Recovery."
        } else {
            Log "Starting the needed services..."
            Start-Service "CCService", "SE3Recovery" -ErrorAction Stop
            Log "Started CCService and SE3Recovery."
        }
        Log "Started all needed services."
    }
    catch {
        Log "There was an issue starting the services or getting the new OCC-Connector GUID:`n$_`nTerminating script."
        exit
    }
}

function Remove-SEDataPath() {
    try {
        Start-Sleep -Seconds 3
        Remove-Item -Path $SEDataPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        Log "There was an issue deleting the ServerEye3 folder:`n$_`nContinuing, since some files might be in use."
    }
}

function ConvertTo-SESensorhub {
    Log "Disabling OCC-Connector service and deleting se3_mac.conf since -MoveAs 'Sensorhub' was passed..."
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

function ConvertTo-SEOCCConnector {
    Log "Enabling OCC-Connector service and creating se3_mac.conf since -MoveAs 'OCC-Connector' was passed..."
    try {
        Set-Service "MACService" -StartupType Automatic -ErrorAction Stop
        Log "OCC-Connector service enabled."
    }
    catch {
        Log "There was an issue enabling the OCC-Connector service:`n$_`nTerminating script."
        exit
    }
    try {
        Set-Content -Path $MACConfigPath -NoNewline -Value @"
customer=$CustomerNumber
name=
description=
secretKey=$SecretKey
guid=
"@
        Log "se3_mac.conf created."
    }
    catch {
        Log "There was an issue creating se3_mac.conf:`n$_`nTerminating script."
        exit
    }
}

function Move-SESensors {
    Log "Moving agents to new container"
    try {
        Log "Getting agents from old container..."
		$Response = Invoke-WebRequest -Method Get -Uri "https://api.server-eye.de/3/container/$OldCCId/agents" -Headers @{ "x-api-key" = $ApiKeyCurrentDistributor } -UseBasicParsing -ErrorAction Stop
        
        # API v3 currently has a bug where agent shadows (Sensorvorschlaege) are returned in addition to real sensors so we need to filter them out by making sure the incarnation is "AGENT" and not "SHADOW"
        $Agents = $Response.Content | ConvertFrom-Json -ErrorAction Stop
        $Agents = $Agents | Where-Object -Property incarnation -eq "AGENT"

        Log "Agents retrieved from old container:"
        $Agents | ForEach-Object { Log "- $($_.name)" }
	}
    catch {
        Log "Failed to get agents from old container. Error: `n$_`n"
	}

    foreach ($Agent in $Agents) {
        try {
            Log "Adding agent '$($Agent.name)' to container..."

            $Body = @{
                parentId = $NewCCId
                type = $Agent.type.agentType
                agentType = $Agent.type.agentType # The v3 agent route requires this property for some reason, even though it seems to be the same as the type property
                name = $Agent.name
            } | ConvertTo-Json

            $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)

            $Response = Invoke-WebRequest -Method Post -Uri "https://api.server-eye.de/3/agent" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Utf8Bytes -ContentType "application/json" -ErrorAction Stop
            $NewAgentId = ($Response.Content | ConvertFrom-Json -ErrorAction Stop).agentId
            Log "Agent '$($Agent.name)' added to container."
        }
        catch {
            Log "Failed to add agent '$($Agent.name)' to container. Continuing with next agent. Error: `n$_`n"
            continue
        }

        Log "Setting interval and pause times of agent '$($Agent.name)'..."
        try {
            $Body = @{
                interval = $Agent.interval
                pause = $Agent.pause
            } | ConvertTo-Json
            
            $Response = Invoke-WebRequest -Method Put -Uri "https://api.server-eye.de/3/agent/$NewAgentId" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Body -ContentType "application/json; charset=utf-8" -UseBasicParsing -ErrorAction Stop
            Log "Interval and pause times set for agent '$($Agent.name)'."
        }
        catch {
            Log "Failed to set interval of '$($Agent.interval)' and pause time of '$($Agent.pause)' for agent '$($Agent.name)'. Error: `n$_`n"
        }

        Log "Setting main settings of agent '$($Agent.name)'..."
        foreach ($Setting in $Agent.settings) {

            # Make sure we don't try to set the value of a password field. Password strings are always encrypted to have a "==PK|" prefix, so we can skip to the next setting if this is the case.
            if ($Setting.settingsValue -like "==PK|*") {
                Log "Setting '$($Setting.settingsKey)' of agent '$($Agent.name)' was skipped since this is a password field!"
                continue
            }

            try {
                $Body = $Setting | Select-Object -Property settingsId, settingsValue | ConvertTo-Json

                $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)

                # Retry up to 5 times in case the agent is not yet available
                $maxTries = 5
                for ($try = 1; $try -le $maxTries; $try++) {
                    try {
                        $Response = Invoke-WebRequest -Method Put -Uri "https://api.server-eye.de/3/agent/$NewAgentId/setting/$($Setting.settingsKey)" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Utf8Bytes -ContentType "application/json; charset=utf-8" -UseBasicParsing -ErrorAction Stop
                        Log "Setting '$($Setting.settingsKey)' of agent '$($Agent.name)' set to '$($Setting.settingsValue)'."
                        break
                    }
                    catch {
                        if ($_.Exception.Response -and ($_.Exception.Response.StatusCode.value__ -eq 404) -and ($try -lt $maxTries)) {
                            Log "Attempt $($try): Agent setting not found, retrying in 2 seconds..."
                            Start-Sleep -Seconds 2
                        } else {
                            throw
                        }
                    }
                }
            }
            catch {
                Log "Failed to set setting '$($Setting.settingsKey)' of agent '$($Agent.name)'. Continuing with next setting. Error: `n$_`n"
                continue
            }
        }
    }
}

function Copy-SEContainerSettings {
    Log "Copying container settings for Sensorhub..."

    try {
        Log "Retrieving container settings..."
        $Response = Invoke-WebRequest -Method Get -Uri "https://api.server-eye.de/3/container/$OldCCId" -Headers @{ "x-api-key" = $ApiKeyCurrentDistributor } -UseBasicParsing -ErrorAction Stop
        $ResponseContent = $Response.Content | ConvertFrom-Json -ErrorAction Stop
        Log "Container settings retrieved."
        try {
            Log "Applying container settings..."

            $Body = @{
                name = $ResponseContent.name
                alertOffline = $ResponseContent.settings.alertOffline
                alertShutdown = $ResponseContent.settings.alertShutdown
                maxHeartbeatTimeout = $ResponseContent.settings.maxHeartbeatTimeout
            } | ConvertTo-Json

            $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)

            Invoke-WebRequest -Method Put -Uri "https://api.server-eye.de/3/container/$NewCCId" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Utf8Bytes -ContentType "application/json; charset=utf-8" -UseBasicParsing -ErrorAction Stop | Out-Null
            Log "Container settings applied."
        }
        catch {
            Log "Error while applying container settings. Error: `n$_`n"
        }
    }
    catch {
        Log "Failed to retrieve Sensorhub settings. Error: `n$_`n"
    }

    if ($IsOCCConnector -and ($MoveAs -eq "OCC-Connector")) {
        Log "Copying container settings for OCC-Connector..."

        try {
            Log "Retrieving container settings..."
            $Response = Invoke-WebRequest -Method Get -Uri "https://api.server-eye.de/3/container/$OldMACId" -Headers @{ "x-api-key" = $ApiKeyCurrentDistributor } -UseBasicParsing -ErrorAction Stop
            $ResponseContent = $Response.Content | ConvertFrom-Json -ErrorAction Stop
            Log "Container settings retrieved."
            try {
                Log "Applying container settings..."

                $Body = @{
                    name = $ResponseContent.name
                    alertOffline = $ResponseContent.settings.alertOffline
                    alertShutdown = $ResponseContent.settings.alertShutdown
                    maxHeartbeatTimeout = $ResponseContent.settings.maxHeartbeatTimeout
                } | ConvertTo-Json

                $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)

                Invoke-WebRequest -Method Put -Uri "https://api.server-eye.de/3/container/$NewMACId" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Utf8Bytes -ContentType "application/json; charset=utf-8" -UseBasicParsing -ErrorAction Stop
                Log "Container settings applied."
            }
            catch {
                Log "Error while applying container settings. Error: `n$_`n"
            }
        }
        catch {
            Log "Failed to retrieve OCC-Connector settings. Error: `n$_`n"
        }
    }
}

function Remove-SEPlannedTasks {
    Log "Removing planned tasks..."
    try {
        Import-Module ScheduledTasks -ErrorAction Stop
    }
    catch {
        Log "Failed to import ScheduledTasks Module, servereye Tasks were not deleted on this system. Error: `n$_`n"
    }
    $Tasks = Get-ScheduledTask -TaskPath "\Server-Eye Tasks" -ErrorAction SilentlyContinue
    $i = 0;
    foreach ($Task in $Tasks) {
        try {
            $ProgressPreference = "SilentlyContinue"
            Unregister-ScheduledTask -TaskName $Task.TaskName -TaskPath "\Server-Eye Tasks" -Confirm:$false -ErrorAction Stop
            $i++
        }
        catch {
            Log "Failed to remove planned task '$($Task.TaskName)'. Error: `n$_`n"
            continue
        }
    }
    Log "Removed $i planned tasks."
}

function Remove-SEAntiRansom {
    $ARRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
    try {
        Log "Checking Anti-Ransom status..."
        if ((Get-ItemPropertyValue -Path $ARRegPath -Name DefaultLevel -ErrorAction Stop) -eq "0") {
            Log "Anti-Ransom is enabled, disabling it..."
            try {
                Set-ItemProperty -Path $ARRegPath -Name "DefaultLevel" -Value "262144" -ErrorAction Stop
                Log "Anti-Ransom has been disabled."
            }
            catch {
                Log "Failed to disable Anti-Ransom. Error: `n$_`n"
            }
        }
        Log "Anti-Ransom is not enabled, no action needed."
    }
    catch {
        Log "Failed to check Anti-Ransom status. Error: `n$_`n"
    }
}

function Remove-SESmartUpdates {
    $PSINIFilePath = "C:\Windows\System32\GroupPolicy\Machine\Scripts"
    $PSINICMDFileName = "scripts.ini"
    $PSINIPSFileName = "psscripts.ini"
    $TriggerPatchRun = "C:\Program Files (x86)\Server-Eye\triggerPatchRun.*"
    $PSCMDINIPath = Join-Path -Path $PSINIFilePath -ChildPath $PSINICMDFileName
    $PSPSINIPath = Join-Path -Path $PSINIFilePath -ChildPath $PSINIPSFileName
    
    $PSINIRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0"
    $SURegKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    
    $Keys = Get-ChildItem -Path $PSINIRegPath -ErrorAction SilentlyContinue
    if ($Keys -and $Keys.PSPath) {
        $KeyToRemove = Get-ItemProperty -Path $Keys.PSPath -Name "Script" -ErrorAction SilentlyContinue | Where-Object -Property Script -like -Value $TriggerPatchRun
    }
    
    Log "Removing Smart Updates script from Group Policy and INI files..."
    if (Test-Path $PSCMDINIPath) {
        Log "Checking $PSINICMDFileName file for Smart Updates script..."
        $content = Get-Content $PSCMDINIPath
        $string = $content | Select-String -Pattern "triggerPatchRun.cmd"
        if ($string) {
            $SetNumber = ($string.ToString()).Substring(0, 1)
            Log "Removing Smart Updates related lines from file..."
            try {
                $content | Select-String -Pattern $SetNumber -NotMatch | Set-Content -Path $PSCMDINIPath -NoNewline
                Log "Smart Updates related lines removed from $PSINICMDFileName file."
            }
            catch {
                Log "Failed to remove Smart Updates related lines from $PSINICMDFileName file. Error: `n$_`n"
            }
        }
        else {
            Log "No Smart Updates related lines in file, nothing to remove."
        }
    }
    if (Test-Path $PSPSINIPath) {
        Log "Checking $PSINIPSFileName file for Smart Updates script..."
        $content = Get-Content $PSPSINIPath
        $string = $content | Select-String -Pattern "triggerPatchRun.ps1"
        if ($string) {
            $SetNumber = ($string.ToString()).Substring(0, 1)
            Log "Removing Smart Updates related lines from file..."
            try {
                $content | Select-String -Pattern $SetNumber -NotMatch | Set-Content -Path $PSPSINIPath -NoNewline
                Log "Smart Updates related lines removed from $PSINIPSFileName file."
            }
            catch {
                Log "Failed to remove Smart Updates related lines from $PSINIPSFileName file. Error: `n$_`n"
            }
        }
        else {
            Log "No Smart Updates related lines in file, nothing to remove."
        }
    }
    
    Log "Removing Smart Updates script from Group Policy registry key..."
    if ($KeyToRemove) {
        if (Test-Path $KeyToRemove.PSPath) {
            try {
                Log "Removing Smart Updates key from Registry..."
                Remove-Item $KeyToRemove.PSPath
                Log "Smart Updates key removed from Registry."
            }
            catch {
                Log "Failed to remove Smart Updates key from Registry. Error: `n$_`n"
            }
        }
    }

    Log "Removing Windows Update related Smart Updates registry key..."
    if (Test-Path $SURegKey) {
        try {
            Remove-Item -Path $SURegKey -Recurse -Force -ErrorAction Stop
            Log "Windows Update related Smart Updates registry key removed."
        }
        catch {
            Log "Failed to remove Windows Update related Smart Updates registry key. Error: `n$_`n"
        }
    } else {
        Log "Windows Update related Smart Updates registry key not found, nothing to remove."
    }

    Log "Calling gpupdate.exe to apply changes..."
    gpupdate.exe /force
}

function Test-SEForSuccessfulRelocation {
    Log "Testing if relocation was successful..."

    Log "Waiting for CCService to generate the new GUID..."
    for ($i = 1; $i -le 120; $i++) {
        try {
            Log "Attempt $($i): Getting new Sensorhub GUID..."
            Start-Sleep -Seconds 10
            $script:NewCCId = (Get-Content $CCConfigPath -ErrorAction Stop | Select-String -Pattern "^guid=").ToString().Split("=")[1].Trim()
            if ((-not $NewCCId) -or ($NewCCId -eq $OldCCId)) {
                if ($i -eq 120) {
                    Log "Failed to get new Sensorhub GUID after 20 minutes, relocation has failed. Terminating script."
                    exit
                }
                continue
            }
            Log "New Sensorhub GUID: $NewCCId"
            break
        }
        catch {
            Log "Failed to retrieve new Sensorhub GUID. Error: `n$_`nTerminating script."
            exit
        }
    }

    if ($MoveAs -eq "OCC-Connector") {
        Log "Waiting for MACService to generate the new OCC-Connector GUID..."
        for ($i = 1; $i -le 120; $i++) {
            try {
                Log "Attempt $($i): Getting new OCC-Connector GUID..."
                Start-Sleep -Seconds 10
                $script:NewMACId = (Get-Content $MACConfigPath -ErrorAction Stop | Select-String -Pattern "^guid=").ToString().Split("=")[1].Trim()
                if ((-not $NewMACId) -or ($NewMACId -eq $OldMACId)) {
                    if ($i -eq 120) {
                        Log "Failed to get new OCC-Connector GUID after 20 minutes, relocation has failed. Terminating script."
                        exit
                    }
                    continue
                }
                Log "New OCC-Connector GUID: $NewMACId"
                break
            }
            catch {
                Log "Failed to retrieve new OCC-Connector GUID. Error: `n$_`nTerminating script."
                exit
            }
        }
    }
    
    Log "Relocation seems to have been successful!"
}

function Remove-SESensorhubContainer {
    Log "Removing old Sensorhub container..."
    try {
        Invoke-WebRequest -Method Delete -Uri "https://api.server-eye.de/3/container/$OldCCId" -Headers @{ "x-api-key" = $ApiKeyCurrentDistributor } -UseBasicParsing -ErrorAction Stop | Out-Null
        Log "Old Sensorhub container removed."
    }
    catch {
        Log "Failed to remove old Sensorhub container. Error: `n$_`n"
    }
}
#endregion

#region Main execution
Log "### Starting Relocate-Container.ps1 script... ###"
Stop-SEServices
if ($IsOCCConnector -and ($MoveAs -eq "Sensorhub")) { ConvertTo-SESensorhub }
elseif ((-not $IsOCCConnector) -and ($MoveAs -eq "OCC-Connector")) { ConvertTo-SEOCCConnector }
Edit-SEConfigFiles
Remove-SEDataPath
Remove-SEPlannedTasks
Remove-SEAntiRansom
Remove-SESmartUpdates
Start-SEServices
Test-SEForSuccessfulRelocation
if (($CopyContainerSettings -eq "true") -and ($ApiKeyCurrentDistributor -or $ApiKeyNewDistributor)) { Copy-SEContainerSettings }
if (($MoveSensors -eq "true") -and ($ApiKeyCurrentDistributor -or $ApiKeyNewDistributor)) { Move-SESensors }
if (($RemoveContainer -eq "true") -and ($ApiKeyCurrentDistributor -or $ApiKeyNewDistributor)) { Remove-SESensorhubContainer }
Log "### Relocate-Container.ps1 script finished. ###"
#endregion
