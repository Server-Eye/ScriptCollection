#Requires -Module ServerEye.PowerShell.Helper
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
	
	.PARAMETER AddCategories
    Kategorien die hinzugefügt werden sollen.

    .EXAMPLE 
    .\ChangeSUSettings.ps1 -AuthToken "ApiKey" -CustomerId "ID des Kunden" -UpdateDelay "Tage für die Verzögerung" -installDelay "Tage für die Installation"
    
    .EXAMPLE
    .\ChangeSUSettings.ps1 -AuthToken "ApiKey" -CustomerId "ID des Kunden" -UpdateDelay "Tage für die Verzögerung" -installDelay "Tage für die Installation" -categories -MICROSOFT
    
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
    [Parameter(Mandatory = $true)]
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
     $AddCategories,
      [Parameter(Mandatory = $true)]
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
        $downloadStrategy,
        $addedCategory,
        $removedCategory
    )

    if ($installDelay) {
        $ViewFilterSetting.installWindowInDays = $installDelay
    } else {
        $ViewFilterSetting.installWindowInDays = $ViewFilterSetting.installWindowInDays
    }

    if ($UpdateDelay) {
        $ViewFilterSetting.delayInstallByDays = $UpdateDelay
    } else {
        $ViewFilterSetting.delayInstallByDays = $ViewFilterSetting.delayInstallByDays
    }

    if ($downloadStrategy) {
        $ViewFilterSetting.downloadStrategy = $downloadStrategy
    } else {
        $ViewFilterSetting.downloadStrategy = $ViewFilterSetting.downloadStrategy
    }

    if ($addedCategory -or $removeCategory) {
        $newSettingList = New-Object System.Collections.Generic.List[PSObject]

        foreach ($cat in $ViewFilterSetting.categories) {
            $newSettingList.Add($cat)
        }

        foreach ($paracat in $addedCategory) {
            $containsCatItem = $newSettingList | Where-Object { $_.id -eq $paracat }

            if (! $containsCatItem) {
                $newSettingList.Add([PSCustomObject]@{ id = $paracat })
            }
        }

        foreach ($paracat in $removeCategory) {
            $containsCatItem = $newSettingList | Where-Object { $_.id -eq $paracat }

            if ($containsCatItem) {
                $predicate = [Predicate[PSObject]]{
                    param($item)
                    $item.id -eq $paracat
                }

                # Use Out-Null to suppress the Write-Output (output the number of removed items)
                $newSettingList.RemoveAll($predicate) | Out-Null


            }
        }

        $ViewFilterSetting.categories = $newSettingList
    }

    $body = $ViewFilterSetting |
        Select-Object -Property installWindowInDays, delayInstallByDays, categories, downloadStrategy, maxScanAgeInDays, enableRebootNotify, maxRebootNotifyIntervalInHours |
        ConvertTo-Json

    $SetCustomerViewFilterSettingURL = "https://pm.server-eye.de/patch/$($ViewFilterSetting.customerId)/viewFilter/$($ViewFilterSetting.vfId)/settings"
    
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

    $output = @()
    $output += "Folgende Einstellungen wurden f�r $($Group.name) gesetzt:"
    $output += "Installationsfenster: $($ViewFilterSetting.installWindowInDays) Tage"
    $output += "Update-Verz�gerung: $($ViewFilterSetting.delayInstallByDays) Tage"
    $output += "Download-Strategie: $($ViewFilterSetting.downloadStrategy)"

    if ($addedCategory) {
        $output += "Hinzugef�gte Update-Kategorien: $addedCategory"
    }

    if ($removeCategory) {
        $output += "Entfernte Update-Kategorien: $removeCategory"
    }

    Write-Output ($output -join ", ")
}


$AuthToken = Test-SEAuth -AuthToken $AuthToken

if ($ViewfilterName) {
    $Groups = Get-SEViewFilters -AuthToken $AuthToken -CustomerID $CustomerID | Where-Object { $_.name -eq $ViewfilterName }
}
else {
    $Groups = Get-SEViewFilters -AuthToken $AuthToken -CustomerID $CustomerID
}


foreach ($Group in $Groups) {
   
  
   
        $GroupSettings = Get-SEViewFilterSettings -AuthToken $AuthToken -CustomerID $CustomerID -ViewFilter $Group
        Write-Debug "$GroupSettings not categories"
    
    
    foreach ($GroupSetting in $GroupSettings) {

        Set-SEViewFilterSetting -AuthToken $AuthToken -ViewFilterSetting $GroupSetting -UpdateDelay $UpdateDelay -installDelay $installDelay -downloadStrategy $downloadStrategy -addedCategory $AddCategories -removedCategory $RemoveCategories
  
    }
}
