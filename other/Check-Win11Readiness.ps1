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
    # Install and import ServerEye.Powershell.Helper module
    if (-not (Get-InstalledModule -Name "ServerEye.Powershell.Helper")) {
        Install-Module -Name ServerEye.Powershell.Helper -Confirm:$false -Force -ErrorAction Stop
        Log "Installed ServerEye.Powershell.Helper module"
    } else {
        Log "ServerEye.Powershell.Helper module is already installed"
    }
    if (-not (Get-Module -Name "ServerEye.Powershell.Helper")) {
        Import-Module -Name ServerEye.Powershell.Helper -Force -ErrorAction Stop
        Log "Imported ServerEye.Powershell.Helper module"
    } else {
        Log "ServerEye.Powershell.Helper module is already imported"
    }
    # Install and import ImportExcel module
    if (-not (Get-InstalledModule -Name "ImportExcel")) {
        Install-Module -Name ImportExcel -Confirm:$false -Force -ErrorAction Stop
        Log "Installed ImportExcel module"
    } else {
        Log "ImportExcel module is already installed"
    }
    if (-not (Get-Module -Name "ImportExcel")) {
        Import-Module -Name ImportExcel -Force -ErrorAction Stop
        Log "Imported ImportExcel module"
    } else {
        Log "ImportExcel module is already imported"
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

# SIG # Begin signature block
# MIIUrAYJKoZIhvcNAQcCoIIUnTCCFJkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAt27MOYevpXygB
# C/55VhYE7tZdz6Z01Db3q2R4DPOumqCCEWcwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# KoZIhvcNAQkEMSIEIKT7uxGPvso/fHgLrfRPYY/SuUlQjsDt6ZOX+EETpuohMA0G
# CSqGSIb3DQEBAQUABIIBgLNE9doWj9HpeKf9f+luDxItQ6lznyXSRV89ho8nz4sF
# TXZSHjLwGOCWcH7dTdgytVKGD/pG3+2qv8a73k9IIJs1qUrXvwQphcXddXI6O5Bu
# ymOEJiHsdPcO/6Ihyn/T0KhG3PtO6JUtg55LFUc3fdYVLHFc7Keq7MR1SA5nOQO/
# nNRNcMSbaooPuN6jK2WV+QL32SdqAVbUhkGV2zTGLukcFrhyiaRgaIYncNQSqOd9
# kq0RG3q0dzwWyh8C0W5oRtP3uKMq3M64k5CK8Jbs3fY9+iTd5te7ca9eVPPTYNC0
# 3s+UIdYVAXUrvibd2sTcyP1EkpnA4xjQX98xpUnOV/iNxh8e4eJJfY6Yi5xMRglS
# 2dUt/Ax2oScjpee7qYPvaGimRB4m7fSAiIlQ1N9W3X5mSj/w1bt/o/V5/wVMCDuX
# 1aXfi4KlbuqViel5E+Xrrt3g1SsG5AHxJknc03Udb674z+4WXYYi5+5QRZ6N4fKF
# HVFO5dHDlWo/iNp8sKtHGQ==
# SIG # End signature block
