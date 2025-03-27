#Requires -RunAsAdministrator
<#
    .SYNOPSIS
    Relocates a container (Sensorhub or OCC-Connector) to a new customer by modifying the configuration files in the servereye directory.
    
    .DESCRIPTION
    Relocates a Sensorhub or OCC-Connector by modifying the configuration files (se3_cc.conf and optionally se3_mac.conf) in the servereye directory.
    The script stops the servereye services, updates the configuration files with the provided customerID, parentGUID, and secretKey, and restarts the services.
    It also supports additional functionality such as moving agents (sensors) to the new container, copying container settings, removing the old container, and handling OCC-Connector-specific configurations.
    Depending on the parameters provided, the script can also convert a system between Sensorhub and OCC-Connector.

    .PARAMETER MoveAs
    Specifies whether the system should be relocated as a Sensorhub or an OCC-Connector. Valid values are "Sensorhub" or "OCC-Connector".

    .PARAMETER MoveSensors
    Indicates whether the agents (sensors) should also be moved to the new container. Pass "true" to move sensors, otherwise leave empty.

    .PARAMETER RemoveContainer
    Indicates whether the old container should be removed after relocation. Pass "true" to remove the Sensorhub container, otherwise leave empty.

    .PARAMETER customerID
    Customer ID of the customer where the system should be relocated.

    .PARAMETER parentGuid
    Container ID of the OCC-Connector where the Sensorhub should be relocated.

    .PARAMETER secretKey
    SecretKey of the customer where the system should be relocated.

    .PARAMETER ApiKeyCurrentDistributor
    The API key of the current distributor. This is required to authenticate API calls for the current distributor.

    .PARAMETER ApiKeyNewDistributor
    The API key of the new distributor. If not provided, the current distributor's API key will be used.
    This parameter doesn't need to be provided if the distributor stays the same.

    .NOTES
    Author  : servereye
    Version : 1.3

    .EXAMPLE
    PS> .\Relocate-Container.ps1 -customerID 42569786 -parentGuid 4f1kg420-2315-28he-89bc-509s20b25f76 -secretKey e12ejgcf-d491-9892-bg83-95ka457938c2
    Relocates the container to the specified customer with the given parent GUID and secret key.
#>

[CmdletBinding()]
Param (

    [Parameter(Mandatory = $true)]
    [string]
    $MoveAs,

    [Parameter(Mandatory = $false)]
    [string]
    $MoveSensors,

    [Parameter(Mandatory = $false)]
    [string]
    $RemoveContainer,

    [Parameter(Mandatory = $true)]
    [string]
    $CustomerID,

    [Parameter(Mandatory = $false)]
    [string]
    $ParentGuid,

    [Parameter(Mandatory = $true)]
    [string]
    $SecretKey,

    [Parameter(Mandatory = $true)]
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
}

# Get the current GUID
$OldCCId = (Get-Content $CCConfigPath | Select-String -Pattern "guid=").ToString().Split("=")[1]
if ($IsOCCConnector) { $OldMACId  = (Get-Content $MACConfigPath | Select-String -Pattern "guid=").ToString().Split("=")[1] }

#Logfile path
$Logpath = "$env:windir\Temp\Relocate-Container.log"
#endregion

#region Function declarations
function Log {
    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
    $LogMessage = "[$Stamp] $LogString"
    Add-Content "$Logpath" -Value $LogMessage
}

function Test-SEServiceStop() {
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

function Edit-SEConfigFiles() {
    $customerString = "customer="
    $parentGuidString = "parentGuid="
    $secretKeyString = "secretKey="
    $guidString = "guid="

    if (($IsOCCConnector) -and ($MoveAs -eq "OCC-Connector")) {
        try {
            Log "Modifying se3_mac.conf..."
            $content = Get-Content "$CCConfigPath" -Raw -ErrorAction Stop
            # Regex magic, replaces each line with the desired string
            $content = $content -replace "$customerString.*", "customer=$customerID"
            $content = $content -replace "$secretKeyString.*", "secretKey=$secretKey"
            $content = $content -replace "\n$guidString.*", "`nguid="
            $content | Set-Content $MACConfigPath
            Log "Successfully modified se3_mac.conf."
        }
        catch {
            Log "There was an issue modifying se3_mac.conf:`n$_`nTerminating script."
            exit
        }
    }

    try {
        Log "Modifying se3_cc.conf..."
        $content = Get-Content "$CCConfigPath" -Raw -ErrorAction Stop
        # Regex magic, replaces each line with the desired string
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

function Stop-SEServices() {
    Log "Making sure all servereye services are stopped..."
    if ($IsOCCConnector) {
        Stop-Service "SE3Recovery", "CCService", "MACService" -ErrorAction SilentlyContinue
    } else {
        Stop-Service "SE3Recovery", "CCService" -ErrorAction SilentlyContinue
    }
    Test-SEServiceStop
    if ($?) {Log "Stopped all services."}
    else {Log "Services are already stopped."}
}

function Start-SEServices() {
    try {
        Log "Starting the needed services..."
        if ($IsOCCConnector) {
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

function Remove-SEDataPath() {
    try {
        Remove-Item -Recurse -Force $SEDataPath -ErrorAction Stop
    }
    catch {
        Log "There was an issue deleting the ServerEye3 folder:`n$_`nTerminating script."
        exit
    }
}

function ConvertTo-SESensorhub {
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

function ConvertTo-SEOCCConnector {
    Log "Enabling OCC-Connector service and creating se3_mac.conf since -MoveAs 'OCC-Connector' was passed..."
    try {
        Set-Service "MACService" -StartupType Automatic -ErrorAction Stop
    }
    catch {
        Log "There was an issue disabling the OCC-Connector service:`n$_`nTerminating script."
        exit
    }
    try {
        Set-Content -Path $MACConfigPath -Value @"
        customer=$CustomerID
        name=
        description=
        secretKey=$SecretKey
        guid=
"@
    }
    catch {
        Log "There was an issue creating se3_mac.conf:`n$_`nTerminating script."
        exit
    }
}

function Move-SESensors {
    Log "Moving agents to new container..."
    try {
        Log "Getting agents from old container..."
		$Response = Invoke-WebRequest -Method Get -Uri "https://api.server-eye.de/3/container/$OldCCId/agents" -Headers @{ "x-api-key" = $ApiKeyCurrentDistributor } -ErrorAction Stop
        $Agents = $Response.Content | ConvertFrom-Json
        Log "Agents retrieved from old container: $($(($Agents | ForEach-Object { $_.name }) -join ', '))"
	}
    catch {
        Log "Failed to get agents from old container. Error: `n$_`nTerminating script."
        exit
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
            $Response = Invoke-WebRequest -Method Post -Uri "https://api.server-eye.de/3/agent" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Body -ContentType "application/json" -ErrorAction Stop
            $NewAgentId = $Response.Content.agentId | ConvertFrom-Json
            Log "Agent $($Agent.name) added to container."
        }
        catch {
            Log "Failed to add agent '$($Agent.name)' to container. Continuing with next agent. Error: `n$_"
            continue
        }

        Log "Setting settings of agent '$($Agent.name)'..."
        foreach ($Setting in $Agent.settings) {
            try {
                $Body = $Setting | Select-Object -Property settingsId, settingsValue | ConvertTo-Json
                Invoke-WebRequest -Method Post -Uri "https://api.server-eye.de/3/agent/$NewAgentId/setting/$($Setting.settingsKey)" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Body -ContentType "application/json" -ErrorAction Stop
            }
            catch {
                Log "Failed to set setting '$($Setting.settingsKey)' of agent '$($Agent.name)'. Continuing with next setting. Error: `n$_"
                continue
            }
        }
    }
}

function Copy-SEContainerSettings {
    Log "Copying container settings for Sensorhub..."

    try {
        Log "Retrieving container settings..."
        Invoke-WebRequest -Method Get -Uri "https://api.server-eye.de/3/container/$OldCCId" -Headers @{ "x-api-key" = $ApiKeyCurrentDistributor } -ErrorAction Stop
    }
    catch {
        Log "Failed to retrieve Sensorhub settings. Error: `n$_"
    }

    try {
        Log "Applying container settings..."
        $Body = @{
            name = $Response.Content.name
            alertOffline = $Response.Content.settings.alertOffline
            alertShutdown = $Response.Content.settings.alertShutdown
            maxHeartbeatTimeout = $Response.Content.settings.maxHeartbeatTimeout
        } | ConvertTo-Json
        Invoke-WebRequest -Method Post -Uri "https://api.server-eye.de/3/container/$NewCCId" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Body -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        Log "Error while applying container settings. Error: `n$_"
    }

    if ($IsOCCConnector -and ($MoveAs -eq "OCC-Connector")) {
        Log "Copying container settings for OCC-Connector..."


        try {
            Log "Retrieving container settings..."
            Invoke-WebRequest -Method Get -Uri "https://api.server-eye.de/3/container/$OldMACId" -Headers @{ "x-api-key" = $ApiKeyCurrentDistributor } -ErrorAction Stop
        }
        catch {
            Log "Failed to retrieve OCC-Connector settings. Error: `n$_"
        }

        try {
            Log "Applying container settings..."
            $Body = @{
                name = $Response.Content.name
                alertOffline = $Response.Content.settings.alertOffline
                alertShutdown = $Response.Content.settings.alertShutdown
                maxHeartbeatTimeout = $Response.Content.settings.maxHeartbeatTimeout
            } | ConvertTo-Json
            Invoke-WebRequest -Method Post -Uri "https://api.server-eye.de/3/container/$NewMACId" -Headers @{ "x-api-key" = $ApiKeyNewDistributor } -Body $Body -ContentType "application/json" -ErrorAction Stop
        }
        catch {
            Log "Error while applying container settings. Error: `n$_"
        }
    }
}

function Remove-SEPlannedTasks {
    Log "Removing planned tasks..."
    $Tasks = Get-ScheduledTask -TaskPath "\Server-Eye Tasks" -ErrorAction SilentlyContinue
    foreach ($Task in $Tasks) {
        try {
            Unregister-ScheduledTask -TaskName $Task.TaskName -TaskPath "\Server-Eye Tasks" -Confirm:$false -ErrorAction Stop
        }
        catch {
            Log "Failed to remove planned task '$($Task.TaskName)'. Error: `n$_"
            continue
        }
    }
}

function Test-SEForSuccessfulRelocation {
    for ($i = 0; $i -lt 100; $i++) {
        if ($MoveAs -eq "Sensorhub") {
            try {
                Log "Attempt $($i + 1): Getting new Sensorhub containerId..."
                $script:NewCCId = (Get-Content $CCConfigPath -ErrorAction Stop | Select-String -Pattern "guid=").ToString().Split("=")[1]
                if ($NewCCId -eq $OldCCId) {
                    Log "New Sensorhub containerId is the same as the old one, relocation has failed. Terminating script."
                    exit
                }
                Log "New Sensorhub containerId: $NewCCId"
                break
            }
            catch {
                Log "Attempt $($i + 1): Failed to get new container GUID, retrying in 3 seconds. Error: `n$_"
                Start-Sleep -Seconds 3
            }
        } elseif ($MoveAs -eq "OCC-Connector") {
            try {
                Log "Attempt $($i + 1): Getting new OCC-Connector containerId..."
                $script:NewMACId = (Get-Content $MACConfigPath -ErrorAction Stop | Select-String -Pattern "guid=").ToString().Split("=")[1]
                if ($NewMACId -eq $OldMACId) {
                    Log "New OCC-Connector containerId is the same as the old one, relocation has failed. Terminating script."
                    exit
                }
                Log "New OCC-Connector containerId: $NewMACId"
                break
            }
            catch {
                Log "Attempt $($i + 1): Failed to get new container GUID, retrying in 3 seconds. Error: `n$_"
                Start-Sleep -Seconds 3
            }
        }
        if ($i -eq 99) {
            Log "Failed to get new containerId(s) after 5 minutes, relocation has most likely failed. Terminating script."
            exit
        }
    }
}

function Remove-SESensorhubContainer {
    Log "Removing old Sensorhub container..."
    try {
        Invoke-WebRequest -Method Delete -Uri "https://api.server-eye.de/3/container/$OldCCId" -Headers @{ "x-api-key" = $ApiKeyCurrentDistributor } -ErrorAction Stop
        Log "Old Sensorhub container removed."
    }
    catch {
        Log "Failed to remove old Sensorhub container. Error: `n$_"
        continue
    }
}
#endregion

#region Main execution
Stop-SEServices
if ($IsOCCConnector -and ($MoveAs -eq "Sensorhub")) { ConvertTo-SESensorhub }
elseif ((-not $IsOCCConnector) -and ($MoveAs -eq "OCC-Connector")) { ConvertTo-SEOCCConnector }
Edit-SEConfigFiles
Remove-SEDataPath
Remove-SEPlannedTasks
Start-SEServices
Test-SEForSuccessfulRelocation
Copy-SEContainerSettings
if ($MoveSensors -eq "true") { Move-SESensors }
if ($RemoveContainer -eq "true") { Remove-SESensorhubContainer }
#endregion

# SIG # Begin signature block
# MIIUrAYJKoZIhvcNAQcCoIIUnTCCFJkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDY0sFeO9sEW52S
# zsqTdjcNrlFKwwyZTlZwr+/hxR8YoaCCEWcwggVvMIIEV6ADAgECAhBI/JO0YFWU
# jTanyYqJ1pQWMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMjEwNTI1MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjBWMQswCQYDVQQG
# EwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdv
# IFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCN55QSIgQkdC7/FiMCkoq2rjaFrEfUI5ErPtx94jGgUW+s
# hJHjUoq14pbe0IdjJImK/+8Skzt9u7aKvb0Ffyeba2XTpQxpsbxJOZrxbW6q5KCD
# J9qaDStQ6Utbs7hkNqR+Sj2pcaths3OzPAsM79szV+W+NDfjlxtd/R8SPYIDdub7
# P2bSlDFp+m2zNKzBenjcklDyZMeqLQSrw2rq4C+np9xu1+j/2iGrQL+57g2extme
# me/G3h+pDHazJyCh1rr9gOcB0u/rgimVcI3/uxXP/tEPNqIuTzKQdEZrRzUTdwUz
# T2MuuC3hv2WnBGsY2HH6zAjybYmZELGt2z4s5KoYsMYHAXVn3m3pY2MeNn9pib6q
# RT5uWl+PoVvLnTCGMOgDs0DGDQ84zWeoU4j6uDBl+m/H5x2xg3RpPqzEaDux5mcz
# mrYI4IAFSEDu9oJkRqj1c7AGlfJsZZ+/VVscnFcax3hGfHCqlBuCF6yH6bbJDoEc
# QNYWFyn8XJwYK+pF9e+91WdPKF4F7pBMeufG9ND8+s0+MkYTIDaKBOq3qgdGnA2T
# OglmmVhcKaO5DKYwODzQRjY1fJy67sPV+Qp2+n4FG0DKkjXp1XrRtX8ArqmQqsV/
# AZwQsRb8zG4Y3G9i/qZQp7h7uJ0VP/4gDHXIIloTlRmQAOka1cKG8eOO7F/05QID
# AQABo4IBEjCCAQ4wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFDLrkpr/NZZILyhAQnAgNpFcF4XmMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBsGA1UdIAQUMBIwBgYE
# VR0gADAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybC5jb21v
# ZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNAYIKwYBBQUHAQEE
# KDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZI
# hvcNAQEMBQADggEBABK/oe+LdJqYRLhpRrWrJAoMpIpnuDqBv0WKfVIHqI0fTiGF
# OaNrXi0ghr8QuK55O1PNtPvYRL4G2VxjZ9RAFodEhnIq1jIV9RKDwvnhXRFAZ/ZC
# J3LFI+ICOBpMIOLbAffNRk8monxmwFE2tokCVMf8WPtsAO7+mKYulaEMUykfb9gZ
# pk+e96wJ6l2CxouvgKe9gUhShDHaMuwV5KZMPWw5c9QLhTkg4IUaaOGnSDip0TYl
# d8GNGRbFiExmfS9jzpjoad+sPKhdnckcW67Y8y90z7h+9teDnRGWYpquRRPaf9xH
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggXSMIIEOqADAgECAhEAt4Sv
# G7AxI7MH8AJVKBjFCDANBgkqhkiG9w0BAQwFADBUMQswCQYDVQQGEwJHQjEYMBYG
# A1UEChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBD
# b2RlIFNpZ25pbmcgQ0EgUjM2MB4XDTIzMDMyMTAwMDAwMFoXDTI1MDMyMDIzNTk1
# OVowaDELMAkGA1UEBhMCREUxETAPBgNVBAgMCFNhYXJsYW5kMSIwIAYDVQQKDBlL
# csOkbWVyIElUIFNvbHV0aW9ucyBHbWJIMSIwIAYDVQQDDBlLcsOkbWVyIElUIFNv
# bHV0aW9ucyBHbWJIMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA0x/0
# zEp+K0pxzmY8FD9pBsw/d6ZMxeqsbQbqhyFx0VcqOvk9ZoRaxg9+ac4w5hmqo2u4
# XmWp9ckBeWPQ/5vXJHyRc23ktX/rBipFNWVf2BFLInDoChykOkkAUVjozJmX7T51
# ZEIhprQ3f88uzAWJnRQiRzL1qikEH7g1hSTt5wj30kNcDVhuhU38sKiBWiTTdcrR
# m9YnYi9N/UIV15xQ94iwkqIPopmmelo/RywDsgkPcO9gv3hzdYloVZ4daBZDYoPW
# 9BBjmx4MWJoPHJcuiZ7anOroabVccyzHoZm4Sfo8PdjaKIQBvV6xZW7TfBXO8Xta
# 1LeF4L2Z1X2uHRIlqJYGyYQ0bKrRNcLJ4V2NqaxRNQKoQ8pH0/GhMd28rr92tiKc
# Re8dMM6aI91kXuPdivT59oCBA0yYNWCDWjn+NVgPGfJFr/v/yqfx6snNJRm9W1DO
# 4JFV9GKMDO8vJVqLqjle91VCPsHfeBExq5cWG/1DrnsfmaCc5npYXoHvC3O5AgMB
# AAGjggGJMIIBhTAfBgNVHSMEGDAWgBQPKssghyi47G9IritUpimqF6TNDDAdBgNV
# HQ4EFgQUJfYD1cPwKBBKOnOdQN2O+2K4rH4wDgYDVR0PAQH/BAQDAgeAMAwGA1Ud
# EwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwSgYDVR0gBEMwQTA1BgwrBgEE
# AbIxAQIBAwIwJTAjBggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMw
# CAYGZ4EMAQQBMEkGA1UdHwRCMEAwPqA8oDqGOGh0dHA6Ly9jcmwuc2VjdGlnby5j
# b20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nQ0FSMzYuY3JsMHkGCCsGAQUFBwEB
# BG0wazBEBggrBgEFBQcwAoY4aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdv
# UHVibGljQ29kZVNpZ25pbmdDQVIzNi5jcnQwIwYIKwYBBQUHMAGGF2h0dHA6Ly9v
# Y3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEBDAUAA4IBgQBTyTiSpjTIvy6OVDj1
# 144EOz1XAcESkzYqknAyaPK1N/5nmCI2rfy0XsWBFou7M3JauCNNbfjEnYCWFKF5
# adkgML06dqMTBHrlIL+DoMRKVgfHuRDmMyY2CQ3Rhys02egMvHRZ+v/lj4w8y1WQ
# 1KrG3W4oaP6Co5mDhcN6oS7eDOc523mh4BkUcKsbvJEFIqNQq6E+HU8qmKXh6Hjy
# AltsxLGJfYdiydI11j8z7+6l3+O241vxJ74KKeWaX+1PXS6cE+k6qJm8sqcDicwx
# m728RbdJQ2TfPS/xz8gsX7c39/lemAEVd9sGNdFPPHjMsvIYb5ed27BdwQjx53xB
# 4reS80v+KA+fBPaUoSIDt/s1RDDTiIRShNvQxdR8HCq3c15qSWprGZ0ivCzi52Ur
# qmIjDpfyMDfX4WanbMwq7iuFL2Kc9Mp6xzXgO1YWkWqh9dH5qj3tjEj1y+2W7SQy
# uEzzrcCUMk+iwlJLX5d52hNr3HnIM9KBulPlYeSQrpjVaA8wggYaMIIEAqADAgEC
# AhBiHW0MUgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdC
# MRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVi
# bGljIENvZGUgU2lnbmluZyBSb290IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAz
# MjEyMzU5NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0
# ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYw
# ggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQCbK51T+jU/jmAGQ2rAz/V/
# 9shTUxjIztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZUKhWThj/yPqy0iSZhXkZ
# 6Pg2A2NVDgFigOMYzB2OKhdqfWGVoYW3haT29PSTahYkwmMv0b/83nbeECbiMXhS
# Otbam+/36F09fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE215wzrK0h1SWHTxPbPuYk
# RdkP05ZwmRmTnAO5/arnY83jeNzhP06ShdnRqtZlV59+8yv+KIhE5ILMqgOZYAEN
# HNX9SJDm+qxp4VqpB3MV/h53yl41aHU5pledi9lCBbH9JeIkNFICiVHNkRmq4Tpx
# twfvjsUedyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+EKv1WuTGwcLmoU3FpOFM
# bmPj8pz44MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9o1M7a5Jnqf2i2/uMSWym
# R8r2oQBMdlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sCAwEAAaOCAWQwggFgMB8G
# A1UdIwQYMBaAFDLrkpr/NZZILyhAQnAgNpFcF4XmMB0GA1UdDgQWBBQPKssghyi4
# 7G9IritUpimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIB
# ADATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EM
# AQQBMEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2Vj
# dGlnb1B1YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5jcmwwewYIKwYBBQUHAQEEbzBt
# MEYGCCsGAQUFBzAChjpodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJs
# aWNDb2RlU2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2Nz
# cC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEABv+C4XdjNm57oRUgmxP/
# BP6YdURhw1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5jUug2oeunbYAowbFC2AKK+cM
# cXIBD0ZdOaWTsyNyBBsMLHqafvIhrCymlaS98+QpoBCyKppP0OcxYEdU0hpsaqBB
# IZOtBajjcw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd099iChnyIMvY5HexjO2Amtsb
# pVn0OhNcWbWDRF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj1lJziVKEoroGs9Mlizg0
# bUMbOalOhOfCipnx8CaLZeVme5yELg09Jlo8BMe80jO37PU8ejfkP9/uPak7VLwE
# LKxAMcJszkyeiaerlphwoKx1uHRzNyE6bxuSKcutisqmKL5OTunAvtONEoteSiab
# kPVSZ2z76mKnzAfZxCl/3dq3dUNw4rg3sTCggkHSRqTqlLMS7gjrhTqBmzu1L90Y
# 1KWN/Y5JKdGvspbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQZH3pwWvqURR8AgQdULUv
# rxjUYbHHj95Ejza63zdrEcxWLDX6xWls/GDnVNueKjWUH3fTv1Y8Wdho698YADR7
# TNx8X8z2Bev6SivBBOHY+uqiirZtg0y9ShQoPzmCcn63Syatatvx157YK9hlcPmV
# oa1oDE5/L9Uo2bC5a4CH2RwxggKbMIIClwIBATBpMFQxCzAJBgNVBAYTAkdCMRgw
# FgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28gUHVibGlj
# IENvZGUgU2lnbmluZyBDQSBSMzYCEQC3hK8bsDEjswfwAlUoGMUIMA0GCWCGSAFl
# AwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkD
# MQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJ
# KoZIhvcNAQkEMSIEILb6EOJWuDU7y+YUCMo6JloDrSlGRwqy/gG/xUuRMW3OMA0G
# CSqGSIb3DQEBAQUABIIBgF/koS02g56agbm3BgIilQ9/0iFynJWMTfaeiSmtfRsO
# IH8osfIZ4XiBEkvCTnBUJsLVr9vATaK4JQVeaJEA3tUgII94j3iynuKFNgNs/iEa
# 4NRoK+akMQ4fACMLaY1EcBqboerGjbfWfmgQ3MZLknxHax1JeE/kOcnZ7nJxeivj
# 4av/0qudr/RU7ZdEm0eWPoOcpSzhkAPEtUnlMr8z5D6ZgOsIKpLnSbNaOTxC/Rx+
# C9Eah+qDz//zjKgjNLqQvoLyN+GwA6wa3tdwi4wENFwHjGV29XQ/tEr16H07rQYn
# vCFdqw+aGt2hdip/ayGXWzPL/Gxzndoql1WQJ0XjNPNtf9EfgMPMAEnvYo6PWUrq
# RULwHKOpVkkttZMxWVum4Wf31/4TwyrRHYt+f0LNvvgJQVNXJRom/R1ip674U9Tv
# pn/lmI1HCTigR3HPlPo49X025iNSZsL1SzjEFy3wD2ivIXsXNI5CnZQ5qBKN2hJH
# xQeBfMaN6ToupedTzE/6Rw==
# SIG # End signature block
