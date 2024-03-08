#Requires -Modules ServerEye.Powershell.Helper, ImportExcel

<# 
    .SYNOPSIS
    Export inventory data from all sensorhubs of a customer into an excel file

    .DESCRIPTION
    This script will read all inventory data of all sensorhubs of a customer and export it into an excel file
    Disclaimer: This script requires two modules, which can be installed from the PowerShell Gallery Repo with the following command:
    PS C:\> Install-Module -Name ServerEye.Powershell.Helper, ImportExcel

    .PARAMETER ApiKey
    The ApiKey of a user that is managing the customer, which inventory data should be extracted from

    .PARAMETER CustomerID
    The CustomerID of the customer (can be found in the URL bar behind /customer/ when selecting a customer via the customer list in the OCC)
    
    .PARAMETER Dest
    The path where the excel file should be saved. Note: A folder called "inventory" will be created in this path, which will contain the excel file

    .NOTES
    Author  : Thomas Krammes, Modified by Patrick Hissler and Leon Zewe - servereye
    Version : 1.1
    
    .EXAMPLE
    PS C:\> .\customerinventory-to-excel.ps1 -ApiKey "e5e06dght-o924-4745-9407-4824ec3c5908" -CustomerID "3a8388cc-e09c-76c1-99aa-53f65acd59a8" -Dest "C:\Users\max.mustermann\Documents"
#>

Param (
    [Parameter(Mandatory=$true)][string]$ApiKey,
    [Parameter(Mandatory=$true)][string]$CustomerID,
    [Parameter(Mandatory=$true)][string]$Dest
)

function Status {
    Param (
        [Parameter(Mandatory=$true)][string]$Activity,
        [Parameter(Mandatory=$true)][int]$Counter,
        [Parameter(Mandatory=$true)][int]$Max,
        [Parameter(Mandatory=$true)][string]$Status,
        [Parameter(Mandatory=$true)][int]$Id,
        [Parameter(Mandatory=$false)][int]$ParentId
    )
    if ($Max) {
        $PercentComplete = (($Counter * 100) / $Max)
    } else {
        $PercentComplete = 100
    }

    if ($PercentComplete -gt 100) {
        $PercentComplete = 100
    }
    if ($ParentId) {
        try { Write-Progress -Activity $Activity -PercentComplete $PercentComplete -Status $Status -Id $Id -ParentId $ParentId } catch {}
    } else {
        Write-Progress -Activity $Activity -PercentComplete $PercentComplete -Status $Status -Id $Id
    }
}

function Inventory {
    Param (
        [Parameter(Mandatory=$true)]$Customer
    )

    $Hubs = Get-SeApiCustomerContainerList -AuthToken $ApiKey -CId $Customer.Cid | Where-Object { $_.Subtype -eq 2 }
    $XlsFile = Join-Path -Path $Dest -ChildPath "inventory\$($Customer.CompanyName).xlsx"

    $CountH = 0
    $HubCount = $Hubs.Count
    $InitFile = $true

    $InventoryAll = @()
    $HostStatusAll = @()

    foreach ($Hub in $Hubs) {
        $CountH++
        Status -Activity "$($CountH)/$($HubCount) Inventarisiere $($Customer.CompanyName)" -Max $HubCount -Counter $CountH -Status $Hub.Name -Id 2 -ParentId 1
        $HubStatus = '' | Select-Object Hub, MachineName, LastDate, Inventory, OsName, IsVM, IsServer, LastRebootUser, Cid
        $HubTemp = Get-SeApiContainer -AuthToken $ApiKey -CId $Hub.Id
        $HubStatus.Hub = $Hub.Name
        $HubStatus.OsName = $HubTemp.OsName
        $HubStatus.MachineName = $HubTemp.MachineName
        $HubStatus.IsVM = $HubTemp.IsVM
        $HubStatus.IsServer = $HubTemp.IsServer
        $HubStatus.Cid = $Hub.Id
        $HubStatus.LastRebootUser = $HubTemp.LastRebootInfo.User
        $State = (Get-SeApiContainerStateListbulk -AuthToken $ApiKey -CId $Hub.Id)
        $LastDate = [datetime]$State.LastDate
        $HubStatus.LastDate = $LastDate
        if ($LastDate -lt ((Get-Date).AddDays(-60)) -or $State.Message -eq 'OCC Connector hat die Verbindung zum Sensorhub verloren') {
            $HubStatus.Inventory = $false
            $HostStatusAll += $HubStatus
            continue
        } else {
            #-----------------------------------------------------------------------------------------
            $ScriptBlock = {
                try {
                    $Inv = (Get-SeApiContainerInventory -AuthToken $args[0] -CId $args[1])
                }
                catch {
                    $Inv = @()
                }
                return $Inv
            }

            $Inventory = Start-Job -ScriptBlock $ScriptBlock -ArgumentList @($ApiKey, $Hub.Id) | Wait-Job -Timeout 5 | Receive-Job
            Get-Job -State Running | Stop-Job
            Get-Job -State Stopped | Remove-Job
            Get-Job -State Completed | Remove-Job
            #------------------------------------------------------------------------------------------------------------------
            if ($Inventory.Count -eq 0) {
                $HubStatus.Inventory = $false
                $HostStatusAll += $HubStatus
                continue
            }
        }

        $HubStatus.Inventory = $true
        $HostStatusAll += $HubStatus

        if (!($InitObjects)) {
            $InventoryAll = @($Customer.CompanyName)
            $InventoryAll = $InventoryAll | Select-Object 'Hosts'
            $ObjectNames = (($Inventory | Get-Member) | Where-Object { $_.MemberType -eq 'NoteProperty' }).Name
            foreach ($ObjectName in $ObjectNames) {
                $InventoryAll = $InventoryAll | Select-Object *, $ObjectName
            }

            $InitObjects = $true
        }

        $Categories = (($Inventory | Get-Member) | Where-Object { $_.MemberType -eq 'NoteProperty' }).Name

        foreach ($CatItem in $Categories) {
            if ($Inventory.$CatItem.Host -ne $null) {
                $SubObject = $Inventory.$CatItem | Select-Object RealHost, *
            } else {
                $SubObject = $Inventory.$CatItem | Select-Object Host, *
            }

            if ($SubObject.Count -gt 1) {
                $Count = $SubObject.Count
                for ($A = 0; $A -le $Count - 1; $A++) {
                    $SubObject[$A].Host = $Hub.Name
                }
            } elseif (!$SubObject) {
            } else {
                $SubObject.Host = $Hub.Name
            }

            if ((Test-Path $XlsFile) -and $InitFile) {
                Export-Excel -Path $XlsFile -KillExcel
                Remove-Item $XlsFile
            }
            $InitFile = $false
            $ObjectWork = @()
            if ($InventoryAll.$CatItem) {
                $ObjectWork = $InventoryAll.$CatItem
            }

            $ObjectWork += $SubObject
            try { $InventoryAll.$CatItem = $ObjectWork } catch {}
            Clear-Variable SubObject
        }
    }

    if (!$InventoryAll) {
       

 $InventoryAll = @($Customer.CompanyName)
        $InventoryAll = $InventoryAll | Select-Object 'Hosts'
    }

    $InventoryAll.Hosts = $HostStatusAll
    $Worksheets = (($InventoryAll | Get-Member) | Where-Object { $_.MemberType -eq 'NoteProperty' }).Name
    $XlsCount = $Worksheets.Count
    $CountX = 0
    $Worksheets = $Worksheets | Where-Object { $_ -ne 'Hosts' }
    $InventoryAll.Hosts | Export-Excel -Path $XlsFile -WorksheetName 'Hosts' -Append -AutoFilter -AutoSize -FreezeTopRow -BoldTopRow -KillExcel
    foreach ($ObjectName in $Worksheets) {
        $CountX++
        Status -Activity "$($CountX)/$($XlsCount) schreibe Daten in Excel: $($Customer.CompanyName).xlsx" -Max $XlsCount -Counter $CountX -Status $ObjectName -Id 2 -ParentId 1
        $InventoryAll.$ObjectName | Export-Excel -Path $XlsFile -WorksheetName $ObjectName -Append -AutoFilter -AutoSize -FreezeTopRow -BoldTopRow -KillExcel
    }
}

if (!$CustomerID) {
    try {
        $Customers = Get-SeApiCustomerlist -AuthToken $ApiKey
    }
    catch {
        Write-Host 'ApiKey falsch'
        Exit
    }
    $CustomerCount = $Customers.Count
} else {
    try {
        $Customers = @((Get-SeApiCustomerlist -AuthToken $ApiKey | Where-Object { $_.CId -eq $CustomerID }))
    }
    catch {
        Write-Host 'ApiKey falsch'
        Exit
    }
    if (!$Customers) {
        Write-Host 'Customer nicht gefunden'
        Exit
    }
    $CustomerCount = 1
}

if (!(Test-Path $Dest)) {
    Write-Host "$Dest nicht gefunden"
}

$InventoryRoot = Join-Path -Path $Dest -ChildPath '\inventory'

if (!(Test-Path $InventoryRoot)) {
    New-Item -Path $InventoryRoot -ItemType "directory" | Out-Null
}

$CountC = 0
$InitObjects = $false

foreach ($Customer in $Customers) {
    $CountC++
    Write-Host $Customer.CompanyName
    Status -Activity "$($CountC)/$($CustomerCount) Inventarisiere" -Max $CustomerCount -Counter $CountC -Status $Customer.CompanyName -Id 1
    Inventory $Customer
}
# SIG # Begin signature block
# MIIq2QYJKoZIhvcNAQcCoIIqyjCCKsYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB1gtQ/bk3NytNg
# kMt0sfwFPSnkVGmMR2dwhhemPE4Vo6CCJHAwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDV0q9Zpfnf70oI
# NAYAasW2aiPh8KEliWTyrOOezyf9TjANBgkqhkiG9w0BAQEFAASCAYBp0+VTQW1H
# erCkCV2ZUcuO5dp1t0o+KViL5vJwIMD0zg4rlMVy6l54NF/fONxsEyPAY6Ar1Apn
# xIAaapBn/0FaklSw/7Fkjb0yIiEJD5vjKrokmA7jMcDDJy2fvcnAIVQM5WdT2q+m
# dxYpufDUNKbiHwocjt2cfAMaphXATzrzz6mVGDWf4kRAyrUJSjWwI+8IeQv8E8kj
# /ZV2UbGR9CzDRK6gEJnIHIRsTrlKH0hlySFQvJqphXEB8+xEIV9owcI6rSsO316a
# OZ9aBk/rBDoLI+tKStItKcLibBadB/ELqC8Jah2cyOFau+sddunpoY4pjLowflG4
# 21HhVoa6cxIcefQKmMkR+zuTbVZTlN/PTp58iMnhsoMTc+vhSdKdUKeSkHJppatx
# c2Oxzb5jClSE4+nfg1oDc7lg5CoOfEOwS341ZYoMKaE0WX3fuwZcl+nSLXK5dp2Y
# NMKxW0hgwbgMD1bJ5djTfxtVO1Tj//qQ2QEC/pr+eZKab3mnW53jxSuhggMgMIID
# HAYJKoZIhvcNAQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQg
# UlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBAhAFRK/zlJ0IOaa/2z9f5WEW
# MA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkq
# hkiG9w0BCQUxDxcNMjQwMzA1MDkzNzA1WjAvBgkqhkiG9w0BCQQxIgQg/e3VGWl5
# Qj4cbeDpVFy6IhTAziUxrQKXnRgLBP7v0+4wDQYJKoZIhvcNAQEBBQAEggIAbVPs
# v2PbIPHPfNtk9ZStvTpeQl+2d7a//W8PWYH4KPlitgF6DZXnhLnhdARHXnlrQoq2
# zC4YrXSIAcDS82obAvbWIfaY7YW7X5OZlU7xyCMWHf2bN7Zm0gYuU7zYKgL8dsAz
# m66CxZP4+wLqhSHB5jab9xPz78awmUBJEwihpqw+Jxh0FnxlHe1dpYyN72u/qquC
# p7hyWgejJeg++3mgohHY/gx77uxZiaQixLzaGGyJk68t9Oka2neca4NaNskSrpcp
# HYfrUQ2metejAZ/RgGIkIsDXj7XzhWbeKlgUZfs7kzzvrmMgyoxx2VJtcUW/Z3kS
# pkEBFgdhHHqOcVXVt0pAIIpzDz8tGD16C3NUlaXLgIEhjPFIIk+MKscCagZN2f11
# S6xl8MWeti94aUS4oSAQ2S3YdKSTj6PbRjkxcv+6Ha54u8DpcZgIrash6X6gNGBx
# d1AEV68B/PJzxFKnDwnW8YuzGwwmtaf5EC7woHm9Fi69mtzh3qfHkYCMGhnL43Gs
# BAxmRPuTobRhoMFZ+ruw5ab7QgahIcUc/PicFR7j+fMhfHIvbmRG8jcFCSTNHlnS
# FzRrFsJ3In/8CX+NsHFnO7/RYZRx+8K5Ui+um736SCr07PAATX3FOs7XGAq74JlV
# fNI2jSQQDrYWoV6D6iy8NocJP8zBuPFawD0e6JU=
# SIG # End signature block
