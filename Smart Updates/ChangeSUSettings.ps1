#Requires -Module ServerEye.PowerShell.helper
<#
    .SYNOPSIS
    Setzt die Einstellungen für die Verzögerung und die Installation Tage im Smart Updates
    
    .DESCRIPTION
    Setzt die Einstellungen für die Verzögerung und die Installation Tage im Smart Updates

    .PARAMETER CustomerId
    ID des Kunden bei dem die Einstellungen geändert werden sollen.

    .PARAMETER ViewfilterName
    Name der Gruppe die geändert werden soll

    .PARAMETER UpdateDelay
    Tage für die Update Verzögerung.

    .PARAMETER installDelay
    Tage für die Installation

    .PARAMETER categories
    Kategorie die in einer Gruppe enthalten sein soll
	
	.PARAMETER downloadStrategy
    Setzt das Download Verhalten auf "FILEDEPOT_ONLY" (Ausschließlich über FileDepot downloaden), "FILEDEPOT_AND_DIRECT" (Hauptsächlich über das FileDepott downloaden, ansonsten über direktem Weg), "DIRECT_ONLY" (Ausschließlich über direktem Weg downloaden ohne FileDepot)
    
    .PARAMETER AuthToken
    Nutzt die Session oder einen ApiKey. Wenn der Parameter nicht gesetzt ist wird die globale Server-Eye Session genutzt.

    .EXAMPLE 
    .\ChangeSUSettings.ps1 -AuthToken "ApiKey" -CustomerId "ID des Kunden" -UpdateDelay "Tage für die Verzögerung" -installDelay "Tage für die Installation"
    
    .EXAMPLE
    .\ChangeSUSettings.ps1 -AuthToken "ApiKey" -CustomerId "ID des Kunden" -UpdateDelay "Tage für die Verzögerung" -installDelay "Tage für die Installation" -categories MICROSOFT
    
    .EXAMPLE
    .\ChangeSUSettings.ps1 -AuthToken "ApiKey" -CustomerId "ID des Kunden" -UpdateDelay "Tage für die Verzögerung" -installDelay "Tage für die Installation" -ViewfilterName "Name einer Gruppe"
    
    .EXAMPLE 
    Get-SECustomer -AuthToken $authtoken| %{.\ChangeSUSettings.ps1 -AuthToken $authtoken -CustomerId $_.CustomerID -ViewfilterName "ThirdParty Server" -UpdateDelay 30 -installDelay 7}
#>



Param ( 
    [Parameter(Mandatory = $true)]
    [alias("ApiKey", "Session")]
    $AuthToken,
    [parameter(ValueFromPipelineByPropertyName, Mandatory = $true)]
    $CustomerId,
    [Parameter(Mandatory = $false)]
    $ViewfilterName,
    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 30)]
    $UpdateDelay,
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 60)]
    $installDelay,
    [Parameter(Mandatory = $false)]
    [ValidateSet("FILEDEPOT_ONLY", "FILEDEPOT_AND_DIRECT", "DIRECT_ONLY")]
    $downloadStrategy,
    [Parameter(Mandatory = $false)]
    [ArgumentCompleter(
            {
                Get-SESUCategories 
            }
        )]
    [ValidateScript(
            {
                $categories = Get-SESUCategories
                $_ -in $categories
            }
        )]
    $categories
)

function Get-SEViewFilters {
    param (
        $AuthToken,
        $CustomerID
    )
    $CustomerViewFilterURL = "https://pm.server-eye.de/patch/$($CustomerID)/viewFilters"
                    
    if ($authtoken -is [string]) {
        try {
            $ViewFilters = Invoke-RestMethod -Uri $CustomerViewFilterURL -Method Get -Headers @{"x-api-key" = $authtoken } | Where-Object { $_.vfId -ne "all" }
            $ViewFilters = $ViewFilters | Where-Object { $_.vfId -ne "all" }
            return $ViewFilters 
        }
        catch {
            Write-Error "$_"
        }
                        
    }
    else {
        try {
            $ViewFilters = Invoke-RestMethod -Uri $CustomerViewFilterURL -Method Get -WebSession $authtoken
            $ViewFilters = $ViewFilters | Where-Object { $_.vfId -ne "all" }
            return $ViewFilters 
                            
                            
        }
        catch {
            Write-Error "$_"
        }
    }
}

function Get-SEViewFilterSettings {
    param (
        $AuthToken,
        $CustomerID,
        $ViewFilter
    )
    $GetCustomerViewFilterSettingURL = "https://pm.server-eye.de/patch/$($customerId)/viewFilter/$($ViewFilter.vfId)/settings"
    if ($authtoken -is [string]) {
        try {
            $ViewFilterSettings = Invoke-RestMethod -Uri $GetCustomerViewFilterSettingURL -Method Get -Headers @{"x-api-key" = $authtoken }
            Return $ViewFilterSettings
        }
        catch {
            Write-Error "$_"
        }
    
    }
    else {
        try {
            $ViewFilterSettings = Invoke-RestMethod -Uri $GetCustomerViewFilterSettingURL -Method Get -WebSession $authtoken
            Return $ViewFilterSettings

        }
        catch {
            Write-Error "$_"
        }
    }
}

function Set-SEViewFilterSetting {
    param (
        $AuthToken,
        $ViewFilterSetting,
        $UpdateDelay,
        $installDelay,
        $downloadStrategy
    )
    if ($installDelay) {
        $ViewFilterSetting.installWindowInDays = $installDelay
    }
    else {
        $ViewFilterSetting.installWindowInDays = $ViewFilterSetting.installWindowInDays
    }
    if ($UpdateDelay) {
        $ViewFilterSetting.delayInstallByDays = $UpdateDelay
    }
    else {
        $ViewFilterSetting.delayInstallByDays = $ViewFilterSetting.delayInstallByDays
    }
    if ($downloadStrategy) {
        $ViewFilterSetting.downloadStrategy = $downloadStrategy
    }
    else {
        $ViewFilterSetting.downloadStrategy = $ViewFilterSetting.downloadStrategy
    }
    $body = $ViewFilterSetting | Select-Object -Property installWindowInDays, delayInstallByDays, categories, downloadStrategy, maxScanAgeInDays, enableRebootNotify, maxRebootNotifyIntervalInHours | ConvertTo-Json

    $SetCustomerViewFilterSettingURL = "https://pm.server-eye.de/patch/$($ViewFilterSetting.customerId)/viewFilter/$($ViewFilterSetting.vfId)/settings"
    if ($authtoken -is [string]) {
        try {
            Invoke-RestMethod -Uri $SetCustomerViewFilterSettingURL -Method Post -Body $body -ContentType "application/json"  -Headers @{"x-api-key" = $authtoken } | Out-Null
            Write-Output "Folgende Einstellungen wurden für $($Group.name) gesetzt: Installationsfenster: $($ViewFilterSetting.installWindowInDays) Tage, Update-Verzögerung: $($ViewFilterSetting.delayInstallByDays) Tage, Download-Strategie: $($ViewFilterSetting.downloadStrategy)"
        }
        catch {
            Write-Error "$_"
        }
    
    }
    else {
        try {
            Invoke-RestMethod -Uri $SetCustomerViewFilterSettingURL -Method Post -Body $body -ContentType "application/json" -WebSession $authtoken | Out-Null
            Write-Output "Folgende Einstellungen wurden für $($Group.name) gesetzt: Installationsfenster: $($ViewFilterSetting.installWindowInDays) Tage, Update-Verzögerung: $($ViewFilterSetting.delayInstallByDays) Tage, Download-Strategie: $($ViewFilterSetting.downloadStrategy)"
        }
        catch {
            Write-Error "$_"
        }
    }
}

$AuthToken = Test-SEAuth -AuthToken $AuthToken

if ($ViewfilterName) {
    $Groups = Get-SEViewFilters -AuthToken $AuthToken -CustomerID $CustomerID | Where-Object { $_.name -eq $ViewfilterName }
}
else {
    $Groups = Get-SEViewFilters -AuthToken $AuthToken -CustomerID $CustomerID
}


foreach ($Group in $Groups) {
    Write-Debug "$categories before If"
    if ($categories) {
        Write-Debug "$categories in IF"
        $GroupSettings = Get-SEViewFilterSettings -AuthToken $AuthToken -CustomerID $CustomerID -ViewFilter $Group | Where-Object { $_.categories.ID -contains $categories }
        Write-Debug "$GroupSettings categories"
    }
    else {
        $GroupSettings = Get-SEViewFilterSettings -AuthToken $AuthToken -CustomerID $CustomerID -ViewFilter $Group
        Write-Debug "$GroupSettings not categories"
    }
    
    foreach ($GroupSetting in $GroupSettings) {

        Set-SEViewFilterSetting -AuthToken $AuthToken -ViewFilterSetting $GroupSetting -UpdateDelay $UpdateDelay -installDelay $installDelay -downloadStrategy $downloadStrategy
  
    }
}
# SIG # Begin signature block
# MIIq2QYJKoZIhvcNAQcCoIIqyjCCKsYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBysquDbePPLJNp
# nuNKMuKicpR3wBZUzz0s6fQ9naEYyqCCJHAwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggWNMIIEdaADAgECAhAOmxiO
# +dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYD
# VQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAi
# BgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAw
# MDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERp
# Z2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsb
# hA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iT
# cMKyunWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGb
# NOsFxl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclP
# XuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCr
# VYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFP
# ObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTv
# kpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWM
# cCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls
# 5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBR
# a2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6
# MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qY
# rhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8E
# BAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5k
# aWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDig
# NoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCg
# v0NcVec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQT
# SnovLbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh
# 65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSw
# uKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAO
# QGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjD
# TZ9ztwGpn1eqXijiuZQwggXSMIIEOqADAgECAhEAt4SvG7AxI7MH8AJVKBjFCDAN
# BgkqhkiG9w0BAQwFADBUMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBM
# aW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgQ0Eg
# UjM2MB4XDTIzMDMyMTAwMDAwMFoXDTI1MDMyMDIzNTk1OVowaDELMAkGA1UEBhMC
# REUxETAPBgNVBAgMCFNhYXJsYW5kMSIwIAYDVQQKDBlLcsOkbWVyIElUIFNvbHV0
# aW9ucyBHbWJIMSIwIAYDVQQDDBlLcsOkbWVyIElUIFNvbHV0aW9ucyBHbWJIMIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA0x/0zEp+K0pxzmY8FD9pBsw/
# d6ZMxeqsbQbqhyFx0VcqOvk9ZoRaxg9+ac4w5hmqo2u4XmWp9ckBeWPQ/5vXJHyR
# c23ktX/rBipFNWVf2BFLInDoChykOkkAUVjozJmX7T51ZEIhprQ3f88uzAWJnRQi
# RzL1qikEH7g1hSTt5wj30kNcDVhuhU38sKiBWiTTdcrRm9YnYi9N/UIV15xQ94iw
# kqIPopmmelo/RywDsgkPcO9gv3hzdYloVZ4daBZDYoPW9BBjmx4MWJoPHJcuiZ7a
# nOroabVccyzHoZm4Sfo8PdjaKIQBvV6xZW7TfBXO8Xta1LeF4L2Z1X2uHRIlqJYG
# yYQ0bKrRNcLJ4V2NqaxRNQKoQ8pH0/GhMd28rr92tiKcRe8dMM6aI91kXuPdivT5
# 9oCBA0yYNWCDWjn+NVgPGfJFr/v/yqfx6snNJRm9W1DO4JFV9GKMDO8vJVqLqjle
# 91VCPsHfeBExq5cWG/1DrnsfmaCc5npYXoHvC3O5AgMBAAGjggGJMIIBhTAfBgNV
# HSMEGDAWgBQPKssghyi47G9IritUpimqF6TNDDAdBgNVHQ4EFgQUJfYD1cPwKBBK
# OnOdQN2O+2K4rH4wDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwIwJTAjBggr
# BgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQBMEkGA1Ud
# HwRCMEAwPqA8oDqGOGh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1Ymxp
# Y0NvZGVTaWduaW5nQ0FSMzYuY3JsMHkGCCsGAQUFBwEBBG0wazBEBggrBgEFBQcw
# AoY4aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljQ29kZVNpZ25p
# bmdDQVIzNi5jcnQwIwYIKwYBBQUHMAGGF2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29t
# MA0GCSqGSIb3DQEBDAUAA4IBgQBTyTiSpjTIvy6OVDj1144EOz1XAcESkzYqknAy
# aPK1N/5nmCI2rfy0XsWBFou7M3JauCNNbfjEnYCWFKF5adkgML06dqMTBHrlIL+D
# oMRKVgfHuRDmMyY2CQ3Rhys02egMvHRZ+v/lj4w8y1WQ1KrG3W4oaP6Co5mDhcN6
# oS7eDOc523mh4BkUcKsbvJEFIqNQq6E+HU8qmKXh6HjyAltsxLGJfYdiydI11j8z
# 7+6l3+O241vxJ74KKeWaX+1PXS6cE+k6qJm8sqcDicwxm728RbdJQ2TfPS/xz8gs
# X7c39/lemAEVd9sGNdFPPHjMsvIYb5ed27BdwQjx53xB4reS80v+KA+fBPaUoSID
# t/s1RDDTiIRShNvQxdR8HCq3c15qSWprGZ0ivCzi52UrqmIjDpfyMDfX4WanbMwq
# 7iuFL2Kc9Mp6xzXgO1YWkWqh9dH5qj3tjEj1y+2W7SQyuEzzrcCUMk+iwlJLX5d5
# 2hNr3HnIM9KBulPlYeSQrpjVaA8wggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJ
# IRwKMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0
# aWdvIExpbWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmlu
# ZyBSb290IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJ
# BgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNl
# Y3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEB
# AQUAA4IBjwAwggGKAoIBgQCbK51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UX
# eWUzCxEeAEZGbEN4QMgCsJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2O
# KhdqfWGVoYW3haT29PSTahYkwmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8j
# e/RV0mIk8XL/tfCK6cPuYHE215wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arn
# Y83jeNzhP06ShdnRqtZlV59+8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV
# /h53yl41aHU5pledi9lCBbH9JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/
# aOs5b4s+ac7IH60B+Ja7TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQI
# Qty/NQd/2yGgW+ufflcZ/ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4
# jKnFH/9gRvd+QOfdRrJZb1sCAwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/
# NZZILyhAQnAgNpFcF4XmMB0GA1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAO
# BgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggr
# BgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIw
# QKA+oDyGOmh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVT
# aWduaW5nUm9vdFI0Ni5jcmwwewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpo
# dHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jv
# b3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEABv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh
# 60BAscjW4HL9hcpkOTz5jUug2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsM
# LHqafvIhrCymlaS98+QpoBCyKppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPY
# fLF/ldYpmlG+vd0xqlqd099iChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6
# fWXhz7DcML4iTAWS+MVXeNLj1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaL
# ZeVme5yELg09Jlo8BMe80jO37PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphw
# oKx1uHRzNyE6bxuSKcutisqmKL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/
# 3dq3dUNw4rg3sTCggkHSRqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfO
# XyXvmPL6E52z1NZJ6ctuMFBQZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdr
# EcxWLDX6xWls/GDnVNueKjWUH3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY
# +uqiirZtg0y9ShQoPzmCcn63Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH
# 2RwwggauMIIElqADAgECAhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3DQEBCwUA
# MGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsT
# EHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9v
# dCBHNDAeFw0yMjAzMjMwMDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJBgNVBAYT
# AlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQg
# VHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE8pE3qZdR
# odbSg9GeTKJtoLDMg/la9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBMLJnOWbfhX
# qAJ9/UO0hNoR8XOxs+4rgISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU5ygt69Ox
# tXXnHwZljZQp09nsad/ZkIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLydkf3YYMZ
# 3V+0VAshaG43IbtArF+y3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFkdECnwHLF
# uk4fsbVYTXn+149zk6wsOeKlSNbwsDETqVcplicu9Yemj052FVUmcJgmf6AaRyBD
# 40NjgHt1biclkJg6OBGz9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9abJTyUpUR
# K1h0QCirc0PO30qhHGs4xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwYSH8UNM/S
# TKvvmz3+DrhkKvp1KCRB7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80VgvCONWPfc
# Yd6T/jnA+bIwpUzX6ZhKWD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5FBASA31f
# I7tk42PgpuE+9sJ0sj8eCXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9Rp6103a5
# 0g5rmQzSM7TNsQIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNV
# HQ4EFgQUuhbZbU2FL3MpdpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7NfjgtJxXWRM
# 3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRw
# Oi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAg
# BgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQAD
# ggIBAH1ZjsCTtm+YqUQiAX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp+3CKDaop
# afxpwc8dB+k+YMjYC+VcW9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9qVbPFXON
# ASIlzpVpP0d3+3J0FNf/q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8ZCaHbJK9
# nXzQcAp876i8dU+6WvepELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6ZJxurJB4m
# wbfeKuv2nrF5mYGjVoarCkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnEtp/Nh4ck
# u0+jSbl3ZpHxcpzpSwJSpzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fxZsNBzU+2
# QJshIUDQtxMkzdwdeDrknq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV77QpfMzmH
# QXh6OOmc4d0j/R0o08f56PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT1ObyF5lZ
# ynDwN7+YAN8gFk8n+2BnFqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkPCr2B2RP+
# v6TR81fZvAT6gt4y3wSJ8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvmfxqkhQ/8
# mJb2VVQrH4D6wPIOK+XW+6kvRBVK5xMOHds3OBqhK/bt1nz8MIIGwjCCBKqgAwIB
# AgIQBUSv85SdCDmmv9s/X+VhFjANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJV
# UzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRy
# dXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTIzMDcx
# NDAwMDAwMFoXDTM0MTAxMzIzNTk1OVowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoT
# DkRpZ2lDZXJ0LCBJbmMuMSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAy
# MzCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKNTRYcdg45brD5UsyPg
# z5/X5dLnXaEOCdwvSKOXejsqnGfcYhVYwamTEafNqrJq3RApih5iY2nTWJw1cb86
# l+uUUI8cIOrHmjsvlmbjaedp/lvD1isgHMGXlLSlUIHyz8sHpjBoyoNC2vx/CSSU
# pIIa2mq62DvKXd4ZGIX7ReoNYWyd/nFexAaaPPDFLnkPG2ZS48jWPl/aQ9OE9dDH
# 9kgtXkV1lnX+3RChG4PBuOZSlbVH13gpOWvgeFmX40QrStWVzu8IF+qCZE3/I+PK
# hu60pCFkcOvV5aDaY7Mu6QXuqvYk9R28mxyyt1/f8O52fTGZZUdVnUokL6wrl76f
# 5P17cz4y7lI0+9S769SgLDSb495uZBkHNwGRDxy1Uc2qTGaDiGhiu7xBG3gZbeTZ
# D+BYQfvYsSzhUa+0rRUGFOpiCBPTaR58ZE2dD9/O0V6MqqtQFcmzyrzXxDtoRKOl
# O0L9c33u3Qr/eTQQfqZcClhMAD6FaXXHg2TWdc2PEnZWpST618RrIbroHzSYLzrq
# awGw9/sqhux7UjipmAmhcbJsca8+uG+W1eEQE/5hRwqM/vC2x9XH3mwk8L9Cgsqg
# cT2ckpMEtGlwJw1Pt7U20clfCKRwo+wK8REuZODLIivK8SgTIUlRfgZm0zu++uuR
# ONhRB8qUt+JQofM604qDy0B7AgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4Aw
# DAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAX
# MAgGBmeBDAEEAjALBglghkgBhv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3Mpdpov
# dYxqII+eyG8wHQYDVR0OBBYEFKW27xPn783QZKHVVqllMaPe1eNJMFoGA1UdHwRT
# MFEwT6BNoEuGSWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0
# ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEB
# BIGDMIGAMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYI
# KwYBBQUHMAKGTGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRy
# dXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcN
# AQELBQADggIBAIEa1t6gqbWYF7xwjU+KPGic2CX/yyzkzepdIpLsjCICqbjPgKjZ
# 5+PF7SaCinEvGN1Ott5s1+FgnCvt7T1IjrhrunxdvcJhN2hJd6PrkKoS1yeF844e
# ktrCQDifXcigLiV4JZ0qBXqEKZi2V3mP2yZWK7Dzp703DNiYdk9WuVLCtp04qYHn
# bUFcjGnRuSvExnvPnPp44pMadqJpddNQ5EQSviANnqlE0PjlSXcIWiHFtM+YlRpU
# urm8wWkZus8W8oM3NG6wQSbd3lqXTzON1I13fXVFoaVYJmoDRd7ZULVQjK9WvUzF
# 4UbFKNOt50MAcN7MmJ4ZiQPq1JE3701S88lgIcRWR+3aEUuMMsOI5ljitts++V+w
# QtaP4xeR0arAVeOGv6wnLEHQmjNKqDbUuXKWfpd5OEhfysLcPTLfddY2Z1qJ+Pan
# x+VPNTwAvb6cKmx5AdzaROY63jg7B145WPR8czFVoIARyxQMfq68/qTreWWqaNYi
# yjvrmoI1VygWy2nyMpqy0tg6uLFGhmu6F/3Ed2wVbK6rr3M66ElGt9V/zLY4wNjs
# HPW2obhDLN9OTH0eaHDAdwrUAuBcYLso/zjlUlrWrBciI0707NMX+1Br/wd3H3GX
# REHJuEbTbDJ8WC9nR2XlG3O2mflrLAZG70Ee8PBf4NvZrZCARK+AEEGKMYIFvzCC
# BbsCAQEwaTBUMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVk
# MSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgQ0EgUjM2AhEA
# t4SvG7AxI7MH8AJVKBjFCDANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEM
# MQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQB
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDgAfydqGXnEBUS
# 9+q+Q07Q/9XgTfZTJsQ83r2um+GKxTANBgkqhkiG9w0BAQEFAASCAYAuR230mLgR
# jkEmlwoAipQAXFc3r/c3+N/oRxTAhX/oO4rC6W6Wqlt2VUXIe1QLzw5eTHzwLA13
# uZ5jscEwtgLNkHCZPliYzjcXCzMxGCXcOJtDDV5oTzYUwXYDdr/29aUCyWUetZqo
# fefitl0rp3BRlNgHEFSgU56349VhG1X39RegCQ7vx0IDhjEe/eF76VFRwm/7huU6
# tlhXOKHo7dL0N8y1OOXwM63C69lNqeExNxcnLkHAPuUMOJ59WSeLGs9g/xqjzKPk
# 3m5Zm+FA7X6qTlh6NHSHv18N6F2U8rKAYm/0R2LUQ/JSdCOJbQaNK2v39X49xagd
# n2Jn/TpQEaHhDJiAqWnZ/hK429UPzKIfteJ+7WVp2OrWd1R5A6oSaEv6wVxeO2vI
# f63CuJwKlgCa66wddimS/4XstcWpixNB9RlctYJaVO7QzABl0d+xmoJm+aulR8yK
# 8j/C+pJEk4FTSInw0MQ97P2Jpa43vt629tO4HQ9t4EHirO0ymhEzy82hggMgMIID
# HAYJKoZIhvcNAQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQg
# UlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBAhAFRK/zlJ0IOaa/2z9f5WEW
# MA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkq
# hkiG9w0BCQUxDxcNMjQwMjI5MTQyNzM5WjAvBgkqhkiG9w0BCQQxIgQg1GhGcOl5
# W9kyab7M32qQrrqYjyu3TbW25oBYsZf7pXcwDQYJKoZIhvcNAQEBBQAEggIAeL3z
# xX/OTxubFhfZkshJF7pllyfaZzYKw208gtrs1ow9jWQyZK0AYjxX5N1VPZBRCUyU
# 13trjy+wjsszJEoN6ClVRhvs09La4Ve1XGKtS8wD0Dh3eOuP9ByDncuwk7gyXjcI
# JRaVr6LA0wTQNbhpdxyt3bbkNdXzR6mskHG+rv5yHKXM9y37aRxx5tuKGZcPxdbi
# PftxKzv46W0ziUMkkbUOks+ZQ3+9Lae/rJXFeyxTzvJhoPJWtwr73MyuV6LpJjh7
# mlNTAwoM/hj3JQzv7SzaO31DanCZwAwBwSKWAbsGTI0oxfzJ9VLDpvKUGoTR01E8
# +8bvuuu6+DfP4HGztsAYJmEuqPR0pNzsidDaCM545ly1eCCLnk5+TM4w2LH4HwJi
# 4ATOfJg9kJFR+9AFUu8vRo37iK3T3DK1kASaFUWR4gQJNTGJxgG70l1QtrB6QnbC
# imObjjdODsNCK2Uj1AWrcrVjlI5LsasJpOZD8v8fG8B06U+7OKgqI1fe29wVUWmU
# TPpwd7wPYtKI0bq9RjHgpsALf0z8OAqnA1aStcdaP6GUDHwjVqF12VX8X0v1Rs2M
# SYSS1L5tWAtAt+j96BNZjejsuF8gOLe0PvymDUxoCVzQySuUmCjZT/YI96SSBPvm
# +tbDiaW9+PRg0DQtAuer/rbs6YrgeIwp0nrP3yM=
# SIG # End signature block
