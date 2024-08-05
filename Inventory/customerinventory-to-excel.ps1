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
    Execute the script for a single customer:
    PS C:\> .\customerinventory-to-excel.ps1 -ApiKey "e5e06dght-o924-4745-9407-4824ec3c5908" -CustomerID "3a8388cc-e09c-76c1-99aa-53f65acd59a8" -Dest "C:\Users\max.mustermann\Documents"

    .EXAMPLE
    Execute the script for every customer currently managed by the user who's ApiKey is provided:
    PS C:\> Get-SECustomer -ApiKey "e5e06dght-o924-4745-9407-4824ec3c5908" | ForEach-Object {.\customerinventory-to-excel.ps1 -ApiKey "e5e06dght-o924-4745-9407-4824ec3c5908" -CustomerId $_.CustomerID -Dest "C:\Users\max.mustermann\Documents\"}
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
        $InventoryAll.$ObjectName | Export-Excel -Path $XlsFile -WorksheetName $ObjectName -Append -AutoFilter -AutoSize -FreezeTopRow -BoldTopRow -KillExcel -NoNumberConversion *
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
# MIIUrAYJKoZIhvcNAQcCoIIUnTCCFJkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDKvSX+68FLEAjs
# cH45wZ2YPo2KBjmERQwN/jN4YndesqCCEWcwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# KoZIhvcNAQkEMSIEIOz8yC4dkyR0TrL7JpQduWXLep2X8e6vH/iYcVRqFcMOMA0G
# CSqGSIb3DQEBAQUABIIBgB5vYs1bG+UKrf4Qd48KJ5K9KutrDWCc4Y4wHblcEUL5
# 8pJ1+0jieCsXVhsbAzdqJDcq37oVLSLKJjsKwps7996Hu+GzzW6SXPNOYxQXFQov
# dFlDBbWVXeLjZ08qJLKQzwIIgD+mCK2HZo5fRSoO50gGQhk9FTWkh5LKYNvysDxN
# EGdrlO0pfJ4DS9gz314IaaxYlQCMjmFGgLkI6hmNutMTEbgfBuPlIm5I+8L3SQ8k
# hkkPrimA5bOUUc0AWDIJvh21KcVGUjNZQN14lgdZAgRtzuDBaoNpEHp8oLq/Rm30
# HLSywMI6IWfiZUj/z+gYCrH8hyFWj3Hr3/dRRCOtmOg5qGgZT9QgaZefAWbi6kEa
# pXg0EbJGTIfo7ycCrVAVwq1u94AytsCzN3vPPdjMNDxmk1YZkmDd1wf98yAbs0+s
# laV8iONGInv9verQxg54z7GPIQG7ncZgj6wRJT8AzScCl7llafolykF60Jqyakbl
# 2wYpiiQ93dCRzljlYxMJxQ==
# SIG # End signature block
