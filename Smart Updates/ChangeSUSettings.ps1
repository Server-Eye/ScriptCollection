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
    $categories,
	[string[]]$AddCategories
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
		$addedCategory
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
	
	  if($addedCategory)
    {
    $newSettingList= New-Object System.Collections.Generic.List[PSObject]
    foreach($cat in $ViewFilterSetting.categories)
    {
     $newSettingList.Add($cat)
    }
    foreach($paracat in $addedCategory) {
        $newSettingList.Add([PSCustomObject]@{ id = $paracat})
    }
    $ViewFilterSetting.categories=$newSettingList
    }

	
    $body = $ViewFilterSetting | Select-Object -Property installWindowInDays, delayInstallByDays, categories, downloadStrategy, maxScanAgeInDays, enableRebootNotify, maxRebootNotifyIntervalInHours | ConvertTo-Json

    $SetCustomerViewFilterSettingURL = "https://pm.server-eye.de/patch/$($ViewFilterSetting.customerId)/viewFilter/$($ViewFilterSetting.vfId)/settings"
    if ($authtoken -is [string]) {
        try {
            Invoke-RestMethod -Uri $SetCustomerViewFilterSettingURL -Method Post -Body $body -ContentType "application/json"  -Headers @{"x-api-key" = $authtoken } | Out-Null
            Write-Output "Folgende Einstellungen wurden für $($Group.name) gesetzt: Installationsfenster: $($ViewFilterSetting.installWindowInDays) Tage, Update-Verzögerung: $($ViewFilterSetting.delayInstallByDays) Tage, Download-Strategie: $($ViewFilterSetting.downloadStrategy), Hinzugefügte Update-Kategorien: $addCategories"
        }
        catch {
            Write-Error "$_"
        }
    
    }
    else {
        try {
            Invoke-RestMethod -Uri $SetCustomerViewFilterSettingURL -Method Post -Body $body -ContentType "application/json" -WebSession $authtoken | Out-Null
            Write-Output "Folgende Einstellungen wurden für $($Group.name) gesetzt: Installationsfenster: $($ViewFilterSetting.installWindowInDays) Tage, Update-Verzögerung: $($ViewFilterSetting.delayInstallByDays) Tage, Download-Strategie: $($ViewFilterSetting.downloadStrategy), Hinzugefügte Update-Kategorien: $addCategories"
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
        $GroupSettings = Get-SEViewFilterSettings -AuthToken $AuthToken -CustomerID $CustomerID -ViewFilter $Group
        Write-Debug "$GroupSettings categories"
    }
    else {
        $GroupSettings = Get-SEViewFilterSettings -AuthToken $AuthToken -CustomerID $CustomerID -ViewFilter $Group
        Write-Debug "$GroupSettings not categories"
    }
    
    foreach ($GroupSetting in $GroupSettings) {

        Set-SEViewFilterSetting -AuthToken $AuthToken -ViewFilterSetting $GroupSetting -UpdateDelay $UpdateDelay -installDelay $installDelay -downloadStrategy $downloadStrategy -addedCategory $AddCategories
  
    }
}
