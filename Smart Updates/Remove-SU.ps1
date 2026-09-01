#Requires -Version 5.0
#Requires -RunAsAdministrator
<#
    .SYNOPSIS
    Removes the Smart Updates update splash entries from the local shutdown script group policy.

    .DESCRIPTION
    Searches the local machine shutdown script policy (registry and scripts.ini) for entries that
    reference ServerEye.SmartUpdates.UpdateSplash.exe, removes them and renumbers the remaining
    entries so the policy stays consistent. Additionally all values of the WindowsUpdate and
    WindowsUpdate\AU policy keys are removed. Finally a gpupdate is triggered.

    .PARAMETER ScriptName
    Optional: Name (or part of the path) of the script to remove from the shutdown scripts.

    .EXAMPLE
    .\Remove-SU.ps1 -Verbose

    .NOTES
    Author  : servereye
    Version : 2.0
#>

[CmdletBinding(SupportsShouldProcess)]
Param(
    [ValidateNotNullOrEmpty()]
    [string]$ScriptName = "ServerEye.SmartUpdates.UpdateSplash.exe"
)

$ScriptsIniPath = "C:\Windows\System32\GroupPolicy\Machine\Scripts\scripts.ini"
$ShutdownRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown"
$WindowsUpdatePolicyPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
)

function Get-IniEncoding {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { "Unicode" } else { "Default" }
}

function Remove-IniScriptEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Verbose "No scripts.ini found at $Path"
        return
    }

    $encoding = Get-IniEncoding -Path $Path
    $lines = @(Get-Content -LiteralPath $Path -Encoding $encoding)

    # Group the flat "<index><Key>=<Value>" lines per ini section so both can be renumbered independently.
    $sections = New-Object System.Collections.Generic.List[object]
    $currentSection = $null
    foreach ($line in $lines) {
        if ($line -match '^\s*\[(.+?)\]\s*$') {
            $currentSection = [PSCustomObject]@{ Name = $Matches[1]; Entries = [ordered]@{} }
            $sections.Add($currentSection)
        }
        elseif ($currentSection -and $line -match '^\s*(\d+)([A-Za-z]+)\s*=(.*)$') {
            $index = $Matches[1]
            if (-not $currentSection.Entries.Contains($index)) { $currentSection.Entries[$index] = [ordered]@{} }
            $currentSection.Entries[$index][$Matches[2]] = $Matches[3]
        }
    }

    $removed = 0
    $content = New-Object System.Collections.Generic.List[string]
    foreach ($section in $sections) {
        $content.Add("[$($section.Name)]")
        $newIndex = 0
        foreach ($index in $section.Entries.Keys) {
            $entry = $section.Entries[$index]
            if ($entry["CmdLine"] -like "*$Pattern*") {
                Write-Verbose "Removing [$($section.Name)] entry $index ($($entry["CmdLine"])) from scripts.ini"
                $removed++
                continue
            }
            foreach ($key in $entry.Keys) { $content.Add("$newIndex$key=$($entry[$key])") }
            $newIndex++
        }
    }

    if ($removed -eq 0) {
        Write-Verbose "No matching entries in $Path"
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, "Remove $removed script entry/entries")) {
        $content | Set-Content -LiteralPath $Path -Encoding $encoding
    }
}

function Remove-RegistryScriptEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Verbose "No shutdown script policy found at $Path"
        return
    }

    foreach ($gpoKey in Get-ChildItem -LiteralPath $Path) {
        $scriptKeys = @(Get-ChildItem -LiteralPath $gpoKey.PSPath |
            Where-Object { $_.PSChildName -match '^\d+$' } |
            Sort-Object { [int]$_.PSChildName })

        $keptEntries = New-Object System.Collections.Generic.List[object]
        $removed = 0
        foreach ($scriptKey in $scriptKeys) {
            if ($scriptKey.GetValue("Script") -like "*$Pattern*") {
                Write-Verbose "Removing registry entry $($scriptKey.Name)"
                $removed++
                continue
            }
            $values = [ordered]@{}
            foreach ($name in $scriptKey.GetValueNames()) {
                $values[$name] = [PSCustomObject]@{
                    Value = $scriptKey.GetValue($name)
                    Kind  = $scriptKey.GetValueKind($name)
                }
            }
            $keptEntries.Add($values)
        }

        if ($removed -eq 0) { continue }

        if (-not $PSCmdlet.ShouldProcess($gpoKey.Name, "Remove $removed script entry/entries")) { continue }

        # Entries have to be recreated because the policy expects gapless, ascending key names.
        foreach ($scriptKey in $scriptKeys) { Remove-Item -LiteralPath $scriptKey.PSPath -Recurse -Force }

        $newIndex = 0
        foreach ($entry in $keptEntries) {
            $newKey = New-Item -Path $gpoKey.PSPath -Name $newIndex -Force
            foreach ($name in $entry.Keys) {
                New-ItemProperty -LiteralPath $newKey.PSPath -Name $name -Value $entry[$name].Value -PropertyType $entry[$name].Kind -Force | Out-Null
            }
            $newIndex++
        }
    }
}

function Clear-RegistryKeyValue {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Verbose "No registry key found at $Path"
        return
    }

    $names = @((Get-Item -LiteralPath $Path).GetValueNames() | Where-Object { $_ })
    if ($names.Count -eq 0) {
        Write-Verbose "No values to remove in $Path"
        return
    }

    foreach ($name in $names) {
        if ($PSCmdlet.ShouldProcess("$Path\$name", "Remove registry value")) {
            Write-Verbose "Removing registry value $Path\$name"
            Remove-ItemProperty -LiteralPath $Path -Name $name -Force
        }
    }
}

Remove-IniScriptEntry -Path $ScriptsIniPath -Pattern $ScriptName
Remove-RegistryScriptEntry -Path $ShutdownRegPath -Pattern $ScriptName

foreach ($policyPath in $WindowsUpdatePolicyPaths) {
    Clear-RegistryKeyValue -Path $policyPath
}

if ($PSCmdlet.ShouldProcess("Local machine policy", "Run gpupdate /force")) {
    Write-Verbose "Calling gpupdate"
    gpupdate.exe /force
}
