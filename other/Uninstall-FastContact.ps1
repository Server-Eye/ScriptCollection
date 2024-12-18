#Requires -RunAsAdministrator
<# 
    .SYNOPSIS
    Uninstall Fast Contact (or an old version of KIM)

    .DESCRIPTION
    This script uninstalls Fast Contact (or an old Version of KIM) from the system.

    .NOTES
    Author  : servereye
    Version : 1.0
#>

$targetDisplayNames = @("Fast Contact", "KIM")
$registryPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($registryPath in $registryPaths) {
    $subKeys = Get-ChildItem -Path $registryPath
    foreach ($subKey in $subKeys) {
        $displayName = Get-ItemProperty -Path $subKey.PSPath -Name DisplayName -ErrorAction SilentlyContinue
        if ($displayName.DisplayName -in $targetDisplayNames) {
            $isFound = $true
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($subKey.PSChildName) /quiet /norestart" -Wait -PassThru
            $exitCode = $process.ExitCode
            if ($exitCode -eq 0) {
                Write-Host "Successfully uninstalled $($displayName.DisplayName)." -ForegroundColor Green
            } else {
                Write-Host "Failed to uninstall $($displayName.DisplayName). Msiexec exit code: $exitCode." -ForegroundColor Red
            }
        }
    }
}

if (-not $isFound) {
    Write-Host "Fast Contact (or an old Version of KIM) wasn't found on this system."
} else {
    Write-Host "Done!"
}