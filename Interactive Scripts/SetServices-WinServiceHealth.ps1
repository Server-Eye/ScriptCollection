#Requires -Module ServerEye.Powershell.Helper

<#
    .SYNOPSIS
    Adds services to the ignore list of multiple Windows Service Health sensors of a single or multiple customers.
        
    .DESCRIPTION
    You can find all details regarding the usage of the script here:
    https://servereye.freshdesk.com/support/solutions/articles/14000149415-windows-dienst-gesundheit-ausschl%C3%BCsse-in-masse-definieren

    .PARAMETER customerId 
    ID of the Customer

    .PARAMETER PathToIgnoreCSV 
    Path to the CSV with a List of the Services, please use Services as the heading in the CSV.
    This parameter is optional.

    .NOTES
    Author  : servereye
    Version : 1.1
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)]
    $customerId,
    [Parameter(Mandatory = $false)]
    $PathToIgnoreCSV,
    [Parameter(ValueFromPipeline = $true)]
    [alias("ApiKey", "Session")]
    $AuthToken
)

$AuthToken = Test-SEAuth -AuthToken $AuthToken
$AgentType = "43C5B1C4-EF06-4117-B84A-7057EA3B31CF"
$NodesList = Get-SeApiMyNodesList -Filter customer, agent, container -AuthToken $AuthToken -listType object
# Combine both customer and managedCustomers into one object, since otherwise we would miss out on the distributor customer
$customers = $NodesList.customer + $NodesList.managedCustomers
$containers = $NodesList.container

if ($customerId) {
    $customers = $customers | Where-Object { $_.id -eq $customerId }
}


# Load all sensorhubs of the selected customer
$customerSensorhubList = $containers | Where-Object { $_.subtype -eq 2 -and $customers.id -contains $_.customerid }

Clear-Host
$tagList = [PSCustomObject]@{
    id       = 0
    name     = "All Sensorhubs of the customer - Don't filter by tag"
    readonly = $false
}

foreach ($sensorhub in $customerSensorhubList) {
    foreach ($tag in $sensorhub.tags) {
        if ($tagList.Name -notcontains $tag.name) {
            $tagList = [Array]$tagList + $tag
        }
    }
}

if ($customers.count -ge 1) {
    Write-Host "Selected customers:" ($customers.name -join ", ") -ForegroundColor Cyan
}
else {
    Write-Host "Selected customer:" $customers.name -ForegroundColor Cyan
}

$i = 0
Write-Host "Which Sensorhubs should the exclusion rule be set on? Choose the desired tag from the list:" -ForegroundColor Yellow
foreach ($tag in $tagList) {
    Write-Host $i ":" $tag.Name
    $i += 1
}
$AddtagInput = Read-Host -Prompt "Enter the number of the tag:"

$selectedAddTag = $tagList[$AddtagInput]
if (!$selectedAddTag) {
    Write-Error "Invalid input!"
    exit 1
}
elseif ($selectedAddTag.id -eq 0) {
    $sensorhubsToUpdate = $customerSensorhubList
}
else {
    $i = 0
    Write-Host "Which Sensorhubs should the exclusion rule NOT be set for? Choose the desired tag from the list:" -ForegroundColor Yellow
    foreach ($tag in $tagList) {
        Write-Host $i ":" $tag.Name
        $i += 1
    }
    $RemovetagInput = Read-Host -Prompt "Enter the number of the tag:"
    $selectedRemoveTag = $tagList[$RemovetagInput]
    if (!($selectedRemoveTag)) {
        Write-Error "Invalid input!"
        exit 1
    }
    elseif ($selectedRemoveTag -eq 0) {
        $sensorhubsToUpdate = $customerSensorhubList | Where-Object { $_.tags.Id -contains $selectedAddTag.id }
    }
    else {
        $sensorhubsToUpdate = $customerSensorhubList | Where-Object { $_.tags.Id -contains $selectedAddTag.id -and $_.tags.Id -notcontains $selectedRemoveTag.id }
    }
}

if (!$sensorhubsToUpdate) {
    Write-Host "$($sensorhubsToUpdate.Count) Sensorhubs with your chosen tag combination:" -ForegroundColor Cyan
    exit
}
else {
    $Agents = $NodesList.agent | Where-Object { $_.subtype -eq $AgentType -and $sensorhubsToUpdate.id -contains $_.parentId }
    Clear-Host
    if ($agents.count -eq 0) {
        Write-Host "$($sensorhubsToUpdate.Count) Sensorhubs with your chosen tag combination; $($agents.count) of these have the Windows Service Health Sensor, no changes need to be made here." -ForegroundColor Cyan
        exit
    }
    else {
        Write-Host "$($sensorhubsToUpdate.Count) Sensorhubs with your chosen tag combination; $($agents.count) of these have the Windows Service Health Sensor." -ForegroundColor Cyan
        Write-Host "Please enter the service names (service names, not display names, e.g. CCService) that should be added to the exception list - Then press enter on an empty line to continue:" -ForegroundColor Yellow
        if ($PathToIgnoreCSV) {
            $pathsInput = (Import-csv -Path $PathToIgnoreCSV).Services
        }
        else {
            $pathsInput = New-Object System.Collections.ArrayList
            $repeatInput = $true
        }
        do {
            $pathInput = Read-Host -Prompt "Service"
            if ([string]::IsNullOrEmpty($pathInput)) {
                if ($pathsInput.Count -eq 0) {
                    Write-Host "You have to enter at least one service!" -ForegroundColor Red
                }
                else {
                    $repeatInput = $false
                }
            }
            else {
                $pathsInput.Add($pathInput) | Out-Null
            }
        } while ($repeatInput -eq $true) 
    }
}


Clear-Host
$count = 0
foreach ($sensorhub in $sensorhubsToUpdate) {
    # Load all AntiRansom agents
    $Agents = $NodesList.agent | Where-Object { $_.Type -eq 3 -and $_.parentId -eq $sensorhub.id -and $_.subtype -eq $AgentType }
    foreach ($agent in $agents) {
        # Get the current path settings of the agent
        $currentPaths = (Get-SeApiAgentSettingList -AuthToken $AuthToken -AId $agent.id | Where-Object key -eq "serviceList").value

        $newClientPaths = $currentPaths

        if ([string]::IsNullOrEmpty($currentPaths)) {
            $newClientPaths = [string]::Join('|,|', $pathsInput)
        }
        else {

            $pathsArray = $currentPaths.Split("|,|")
            foreach ($path in $pathsInput) {
                # Check for existings paths
                if (!$pathsArray.contains($path)) {
                    $newClientPaths = $newClientPaths + "|,|" + $path
                    Write-Debug ("Added $path")
                }
                else {
                    Write-Debug ("Skip $path")
                }
            }
        }

        if ($currentPaths -ne $newClientPaths) {
            $count += 1
            Set-SeApiAgentSetting -AuthToken $AuthToken -AId $agent.id -key "serviceList" -value $newClientPaths | Out-Null
            Write-Host "Exception for $($sensorhub.name) has been added" -ForegroundColor Green
            Write-Debug ("New paths: $newClientPaths")
        }
        else {
            Write-Host "Skipped $($sensorhub.name)" -ForegroundColor DarkYellow
        }
    }
}

Write-Host "Added exceptions for a total of $count sensors." -ForegroundColor Cyan
Write-Host "Done. Bye!" -ForegroundColor Green

# SIG # Begin signature block
# MIIUrAYJKoZIhvcNAQcCoIIUnTCCFJkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCnApOXeBhSj+Hj
# JBXAS9WSVg8fsQHVf2Sxi8LSAxtcuqCCEWcwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# KoZIhvcNAQkEMSIEIHIY/QBjL1b6TPgQaJqs6TBeS4T0Bzzu0zpYpR+Bc9BJMA0G
# CSqGSIb3DQEBAQUABIIBgJPcORHMxrRJD2h6UJ4+GfotMsUbDuVZ7nx/QjZXHIzS
# yN6sTexiZgKUfwc9Wvp1+xmuHtSf9lIWcQd4TaZWkQR+fUzC/ioUadzMLXUHgmTq
# zh89G2Bj8K9m9ASU8exeYtdSo7VwwTeuOIQrLYNsQiiF7bv2qvTxD3nnfp1/O4z/
# 9/6VZluhXITENRRGNOdPduRw/kjKM90dEX0iyj/hN5GC+SiNbz/J44PKhXvQhEN7
# x1kiv2JlcepQaX5UZgGwvZ7BFjuNG9CaenNW+IwhAlu0FAjqgB+qsaFRt2Zkr3hD
# eju5cT69cBbO+x1gtzoyeCPlydHFSrP+ORYBlN0qYy/s9OAQkYC9F6uA8xbpvoZq
# yWF1acFqiwqJJw+JcsnuvJ0ukG/11F2UDlq+cGmt+3UfeNw8Gllkc+2ZR7GTxV+k
# C43vlSxMIJSCXtEknP+YRs+SYh3GcMRdcujXsGT9czpFh+4ViCuHOD4rW829LVoq
# lR/WEg/7tah2GxE8xsaASQ==
# SIG # End signature block
