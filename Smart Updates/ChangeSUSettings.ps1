#Requires -Module ServerEye.PowerShell.Helper
<#
    .SYNOPSIS
    Dieses Skript setzt Einstellungen fuer Smart Updates Gruppen
    
    .DESCRIPTION
    Mit diesem Skript koennen pro Kunde oder kundenuebergreifend Einstellungen fuer Smart Updates Gruppen gesetzt werden.
    Unterstuetzt werden alle Einstellungen, die sich im OCC taetigen lassen.
    Weitere Infos: https://servereye.freshdesk.com/support/solutions/articles/14000115738-anleitung-smart-updates-gruppeneinstellungen-in-masse-definieren

    .PARAMETER AuthToken
    Nutzt die Session oder einen ApiKey. Wenn der Parameter nicht gesetzt ist wird die globale servereye Session genutzt.

    .PARAMETER CustomerId
    Die Kunden ID des Kunden, bei dem die Einstellungen geaendert werden sollen. Hier koennen auch mehrere Kunden mitgegeben werden, indem Get-SECustomer an das Skript gepiped wird.

    .PARAMETER ViewFilterName
    Der Name der Gruppe, die angepasst werden soll.

    .PARAMETER DelayInstallByDays
    Dauer, um die die Installation von Updates verzoegert wird. Massgeblich ist der Tag, an dem das Update veroeffentlicht wurde.

    .PARAMETER InstallWindowInDays
    Zeitraum fuer die Installation, bevor ein Alarm ausgeloest wird.

    .PARAMETER EnableRebootNotify
    Bei ausstehenden Updates wird dem Benutzer ein Hinweis auf einen erforderlichen Neustart des Systems angezeigt.

    .PARAMETER MaxRebootNotifyIntervalInHours
    Stunden bis dem Benutzer der Hinweis erneut angezeigt wird.

    .PARAMETER DelayRebootNotifyByDays
    Zeitraum in dem der Benutzer auf einen Systemneustart hingewiesen wird, bevor ein Alarm ausgeloest wird. Das Abbrechen der Installation ist dann nicht mehr moeglich.

    .PARAMETER MaxScanAgeInDays
    Ab wie vielen Tagen ohne Scan moechtest du einen Alarm?

    .PARAMETER DownloadStrategy
    Waehle aus ueber welche Wege die Updates heruntergeladen werden duerfen:
    "FILEDEPOT_ONLY" (Ausschliesslich ueber das FileDepot downloaden),
    "FILEDEPOT_AND_DIRECT" (Primaer ueber das FileDepot downloaden, als Fallback ueber den direkten Weg),
    "DIRECT_ONLY" (Ausschliesslich ueber den direkten Weg downloaden ohne FileDepot)

    .PARAMETER AddCategories
    Update Kategorien die hinzugefuegt werden sollen.

    .PARAMETER RemoveCategories
    Update Kategorien die entfernt werden sollen.

    .EXAMPLE
    PS> .\ChangeSUSettings.ps1 -AuthToken "ApiKey" -CustomerId "ID des Kunden" -DelayInstallByDays "Tage fuer die Verzoegerung" -InstallWindowInDays "Tage fuer die Installation"
    
    .EXAMPLE
    PS> .\ChangeSUSettings.ps1 -AuthToken "ApiKey" -CustomerId "ID des Kunden" -DelayInstallByDays "Tage fuer die Verzoegerung" -InstallWindowInDays "Tage fuer die Installation" -AddCategories JABRA_DIRECT -RemoveCategories EDGE
    
    .EXAMPLE
    PS> .\ChangeSUSettings.ps1 -AuthToken "ApiKey" -CustomerId "ID des Kunden" -DelayInstallByDays "Tage fuer die Verzoegerung" -InstallWindowInDays "Tage fuer die Installation" -ViewfilterName "Name einer Gruppe"
    
    .EXAMPLE
    PS> .\Get-SECustomer -AuthToken "ApiKey" | ForEach-Object {.\ChangeSUSettings.ps1 -AuthToken $authtoken -CustomerId $_.CustomerID -ViewfilterName "Name einer Gruppe" -DelayInstallByDays 30 -InstallWindowInDays 7}
#>

Param ( 
    [Parameter(Mandatory = $true)]
    [alias("ApiKey", "Session")]
    [string]$AuthToken,

    [parameter(ValueFromPipelineByPropertyName, Mandatory = $true)]
    [string]$CustomerId,

    [Parameter(Mandatory = $false)]
    [string]$ViewFilterName,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 60)]
    [int]$DelayInstallByDays,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 60)]
    [int]$InstallWindowInDays,

    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false")]
    [string]$EnableRebootNotify,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 24)]
    [int]$MaxRebootNotifyIntervalInHours,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 60)]
    [int]$DelayRebootNotifyByDays,

    [Parameter(Mandatory = $false)]
    [ValidateRange(2, 6)]
    [int]$MaxScanAgeInDays,

    [Parameter(Mandatory = $false)]
    [ValidateSet("FILEDEPOT_ONLY", "FILEDEPOT_AND_DIRECT", "DIRECT_ONLY")]
    [string]$DownloadStrategy,

    [Parameter(Mandatory = $false)]
    [ArgumentCompleter(
            {
               Get-SESUCategories 
            }
        )]
    $AddCategories,

    [Parameter(Mandatory = $false)]
    [ArgumentCompleter(
            {
               Get-SESUCategories 
            }
        )]
    $RemoveCategories
)

function Get-SEViewFilters {
    param (
        $AuthToken,
        $CustomerID
    )
    $CustomerViewFilterURL = "https://pm.server-eye.de/patch/$($CustomerID)/viewFilters"
          
	Write-Verbose "Calling API to retrieve view filters for customer $CustomerID"
          
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
    
	Write-Verbose "Fetching settings for view filter '$($ViewFilter.name)' (ID: $($ViewFilter.vfId))"

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
        $DelayInstallByDays,
        $InstallWindowInDays,
        $DelayRebootNotifyByDays,
        $DownloadStrategy,
        $AddedCategories,
        $RemovedCategories,
        $MaxScanAgeInDays,
        $EnableRebootNotify,
        $MaxRebootNotifyIntervalInHours
    )

	Write-Verbose "Preparing settings payload for view filter ID: $($ViewFilterSetting.vfId)"

    if ($InstallWindowInDays) {
        $ViewFilterSetting.installWindowInDays = $InstallWindowInDays
    } else {
        $ViewFilterSetting.installWindowInDays = $ViewFilterSetting.installWindowInDays
    }

    if ($DelayInstallByDays) {
        $ViewFilterSetting.delayInstallByDays = $DelayInstallByDays
    } else {
        $ViewFilterSetting.delayInstallByDays = $ViewFilterSetting.delayInstallByDays
    }

    if ($MaxScanAgeInDays) {
        $ViewFilterSetting.maxScanAgeInDays = $MaxScanAgeInDays
    } else {
        $ViewFilterSetting.maxScanAgeInDays = $ViewFilterSetting.maxScanAgeInDays
    }
    
    if ($EnableRebootNotify) {
        # We need to convert the string to a boolean
        if ($EnableRebootNotify -eq "true") {
            $EnableRebootNotify = $true
        } elseif ($EnableRebootNotify -eq "false") {
            $EnableRebootNotify = $false
        }
        $ViewFilterSetting.enableRebootNotify = $EnableRebootNotify
    } else {
        $ViewFilterSetting.enableRebootNotify = $ViewFilterSetting.enableRebootNotify
    }

    if ($MaxRebootNotifyIntervalInHours) {
        $ViewFilterSetting.maxRebootNotifyIntervalInHours = $MaxRebootNotifyIntervalInHours
    } else {
        $ViewFilterSetting.maxRebootNotifyIntervalInHours = $ViewFilterSetting.maxRebootNotifyIntervalInHours
    }

    if ($DelayRebootNotifyByDays) {
        # We need to calculate this value because of what the backend expects
        $ViewFilterSetting.delayRebootNotifyByDays = $ViewFilterSetting.installWindowInDays - $DelayRebootNotifyByDays
    } else {
        $ViewFilterSetting.delayRebootNotifyByDays = $ViewFilterSetting.delayRebootNotifyByDays
    }

    if ($DownloadStrategy) {
        $ViewFilterSetting.downloadStrategy = $DownloadStrategy
    } else {
        $ViewFilterSetting.downloadStrategy = $ViewFilterSetting.downloadStrategy
    }

    if ($AddedCategories -or $RemovedCategories) {
        $newSettingList = New-Object System.Collections.Generic.List[PSObject]

        foreach ($cat in $ViewFilterSetting.categories) {
            $newSettingList.Add($cat)
        }

        foreach ($paracat in $AddedCategories) {
            $containsCatItem = $newSettingList | Where-Object { $_.id -eq $paracat }

            if (! $containsCatItem) {
                $newSettingList.Add([PSCustomObject]@{ id = $paracat })
            }
        }

        foreach ($paracat in $RemovedCategories) {
            $containsCatItem = $newSettingList | Where-Object { $_.id -eq $paracat }

            if ($containsCatItem) {
                $predicate = [Predicate[PSObject]] {
                    param($item)
                    $item.id -eq $paracat
                }
                $newSettingList.RemoveAll($predicate) | Out-Null
            }
        }

        $ViewFilterSetting.categories = $newSettingList
    }

    $body = $ViewFilterSetting |
        Select-Object -Property installWindowInDays, delayInstallByDays, categories, downloadStrategy, maxScanAgeInDays, enableRebootNotify, maxRebootNotifyIntervalInHours, delayRebootNotifyByDays |
        ConvertTo-Json

    $SetCustomerViewFilterSettingURL = "https://pm.server-eye.de/patch/$($ViewFilterSetting.customerId)/viewFilter/$($ViewFilterSetting.vfId)/settings"
    
	Write-Verbose "Sending updated settings to Server-Eye API: $SetCustomerViewFilterSettingURL"
	
    if ($AuthToken -is [string]) {
        try {
            Invoke-RestMethod -Uri $SetCustomerViewFilterSettingURL -Method Post -Body $body -ContentType "application/json" -Headers @{"x-api-key" = $AuthToken } | Out-Null
        } catch {
            Write-Error "$_"
        }
    } else {
        try {
            Invoke-RestMethod -Uri $SetCustomerViewFilterSettingURL -Method Post -Body $body -ContentType "application/json" -WebSession $AuthToken | Out-Null
        } catch {
            Write-Error "$_"
        }
    }

    Write-Host "Kunde: $((Get-SeApiCustomer -AuthToken $AuthToken -CId $CustomerId).companyName)" -ForegroundColor Green
    Write-Host "Folgende Einstellungen wurden fuer die Gruppe '$($Group.name)' gesetzt:" -ForegroundColor Yellow
    Write-Host "Updateverzoegerung: $($ViewFilterSetting.delayInstallByDays) Tag(e)"
    Write-Host "Installationszeitfenster: $($ViewFilterSetting.installWindowInDays) Tag(e)"
    Write-Host "Neustart-Hinweis anzeigen: $($ViewFilterSetting.enableRebootNotify)"
    Write-Host "Neustart-Hinweis Tage vor Alarmierung: $($ViewFilterSetting.installWindowInDays - $ViewFilterSetting.delayRebootNotifyByDays) Tag(e)"
    Write-Host "Neustart-Hinweis Stunden bis zur erneuten Anzeige: $($ViewFilterSetting.maxRebootNotifyIntervalInHours) Stunde(n)"
    Write-Host "Maximale Tage ohne Scan: $($ViewFilterSetting.maxScanAgeInDays) Tag(e)"
    Write-Host "Downloadverhalten: $($ViewFilterSetting.downloadStrategy)"

    if ($addedCategories) {
        Write-Host "Hinzugefuegte Update Kategorien: $addedCategories"
    }

    if ($removedCategories) {
        Write-Host "Entfernte Update Kategorien: $removedCategories"
    }

    Write-Host ""
}


$AuthToken = Test-SEAuth -AuthToken $AuthToken

if ($ViewFilterName) {
    $Groups = Get-SEViewFilters -AuthToken $AuthToken -CustomerID $CustomerID | Where-Object { $_.name -eq $ViewFilterName }
} else {
    $Groups = Get-SEViewFilters -AuthToken $AuthToken -CustomerID $CustomerID
}

foreach ($Group in $Groups) {
        $GroupSettings = Get-SEViewFilterSettings -AuthToken $AuthToken -CustomerID $CustomerID -ViewFilter $Group
    foreach ($GroupSetting in $GroupSettings) {
        Set-SEViewFilterSetting -AuthToken $AuthToken -ViewFilterSetting $GroupSetting -DelayInstallByDays $DelayInstallByDays -InstallWindowInDays $InstallWindowInDays -DownloadStrategy $DownloadStrategy -AddedCategories $AddCategories -RemovedCategories $RemoveCategories -MaxScanAgeInDays $MaxScanAgeInDays -EnableRebootNotify $EnableRebootNotify -MaxRebootNotifyIntervalInHours $MaxRebootNotifyIntervalInHours -DelayRebootNotifyByDays $DelayRebootNotifyByDays
    }
}

# SIG # Begin signature block
# MIIUrAYJKoZIhvcNAQcCoIIUnTCCFJkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCj2fnDWo0UUiIm
# YUMxg3KKfiQE4awGNCBvsCbDWImjt6CCEWcwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# KoZIhvcNAQkEMSIEIHqcUA5Kukxa2eMgSp6JMy2M0PFuBLhRvX9EFa5qMxguMA0G
# CSqGSIb3DQEBAQUABIIBgBhcIiY4KYpF5pp/mxZvO49BRmPndWWmQ43agNm542ZB
# /lzMglx1vledfoCxej08kWKDPwp/gIfrU1YPeRPNTLbbu7ARAUFyTh1bFmdDHIK0
# Jw4yfiivYCWPWcMxguL1tU37mUurjdSNyx/2ykyJilBxsSeJ0Gal1A52QdZXjJvc
# COJ7VY02U11CqssgnYKBJbRI66kv7mWQnwjMKEPfvcYLNI5CkhqJFeYxwnqG7yKv
# DsWGUCkf1UWEPoaTV1i9piq14L1gf7TXka5PS9rAmep3MO2RobLfrUw7kr/ALv6d
# /E2H1M2+/5M6Sad85vLE79vhGoDJtE4D/iLbi/p9Z6RvC6H+UxBitZOjHsXhO2Qm
# plqj61mSwJxt1QFLYz/XC4QI8eCZor75+cm6Z1yF6cJjDjMK4uRUNlpuWsr7r+lV
# QYJOkotJ9XFjp3eN4fobw7OYk91vNf/F4z5odmLaUu+WunRrb2XaO7FB4Nxfxsb3
# Cevv9/Azq86hP6Y7bfzMGw==
# SIG # End signature block
