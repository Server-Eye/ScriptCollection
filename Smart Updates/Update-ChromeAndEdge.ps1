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

if (Test-Path "C:\ProgramData\ServerEye3\logs") {
    $LogPath = "C:\ProgramData\ServerEye3\logs\Update-ChromeAndEdge.log"
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
            Log "Starting Edge Updater..."
            Start-Process -FilePath "C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe" `
            -argumentlist "/silent /install appguid={56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}&appname=Microsoft%20Edge&needsadmin=True" -ErrorAction Stop
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
# SIG # Begin signature block
# MIIUrAYJKoZIhvcNAQcCoIIUnTCCFJkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDKVDG3d9mUbcf1
# gHBtjL21uHqE+P4GKT7TRXNtHMPva6CCEWcwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# KoZIhvcNAQkEMSIEIGsaLpmRz7vzpG8Q2Eow0SLBp6UU1Bg/R7ZvNn6Ay7++MA0G
# CSqGSIb3DQEBAQUABIIBgHO9VJOjthRMC87294IUCXkoKe3DJGFTB16VP5TpG2Yi
# EmN8mB5hhu+diq727+ZQaf9McWQlgXUP8aqnEmx2mQkLfDARSQpkMrh+/79oOZWg
# Nz9uKpMJivtXr+8GbcSTo/aVIANWPoeGeIpbNX+9o7yBceYbDZlsxJo/m1JFdk+a
# EECuqW7PCG24E5yHAGQgLfuRE9W/yEnUdhBGS/bB5+yZN6DzLzo5vLXwXFcE1kRJ
# +tl2uXVRUVjLuWqzAqmEc1Wd1tUyoegiEmQ1pwXbJuJrS3WtrwLVpv0uY6Dbjvjx
# Cu1Co4MUiauu7gJ6kNIftAJHCN7HoqWdlkAPEAKPsEcSnAsITBdk5GtNqaKalgna
# U7lyAwqyIWLGX0pSTiAkECuwsGw+RYzzFyxhfSTFTILHXvbBSvxqMHIeUq6xfI7p
# n6GnC49JCcS0+kGxgKKzVstKNEcCrKq3uWCAhtksDku7CBohSZnVEd4isiQATOwn
# DbB+5uQGbEDq+A924+DVZA==
# SIG # End signature block
