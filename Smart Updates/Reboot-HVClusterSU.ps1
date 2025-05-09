#region Variables
$Servers = Get-ClusterResource | Where-Object { $_.ResourceType -like "Virtual Machine" }
$PreferredHosts = Get-ClusterGroup | Get-ClusterOwnerNode
$File = $MyInvocation.MyCommand.Path
$Running = Get-Clusternode | Where-Object State -NotContains "Up"

$EventSourceName = "ServerEye-Custom"
$Script:_SilentOverride = $true
$Script:_SilentEventlog = $true
if (Test-Path "C:\ProgramData\ServerEye3") {
    $_LogFilePath = "C:\ProgramData\ServerEye3\logs\smartUpdates.Clusterrestart.temp"
} else {
    $_LogFilePath = "C:\ProgramData\ServerEye\logs\smartUpdates.Clusterrestart.temp"
}

$DataStorage = Get-ChildItem "C:\ClusterStorage"
$DataStorage = $DataStorage[0].FullName
$ScriptRunning = "$DataStorage\scriptrunning.txt"
#endregion

#region Functions
function Write-Log {
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0)]
        [string] $Message,
        
        [bool] $Silent = $_SilentOverride,
        [bool] $SilentEventlog = $_SilentEventlog,
        [System.ConsoleColor] $ForegroundColor,
        [switch] $NoNewLine,
        [Parameter(Position = 1)]
        [int] $EventID = 1000,
        [Parameter(Position = 1)]
        [string] $Source,
        [Parameter(Position = 3)]
        [System.Diagnostics.EventLogEntryType] $EntryType = ([System.Diagnostics.EventLogEntryType]::Information),
        [string] $LogFilePath = $_LogFilePath
    )
  
    if (-not $SilentEventlog) {
        try { Write-EventLog -Message $Message -LogName 'Application' -Source $Source -Category 0 -EventId $EventID -EntryType $EntryType -ErrorAction Stop }
        catch { }
    }
    
    try { "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $EntryType $EventID - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop }
    catch { }
    
    if (-not $Silent) {
        $Splat = @{ }
        $Splat['Object'] = $Message
        if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $Splat['ForegroundColor'] = $ForegroundColor }
        if ($PSBoundParameters.ContainsKey('NoNewLine')) { $Splat['NoNewLine'] = $NoNewLine }
        Write-Output @Splat
    }
}

function Move_VMs {
    $Servers = Get-ClusterResource | Where-Object { $_.ResourceType -like "Virtual Machine" }
    $SingleServer = $Servers | Where-Object OwnerNode -like $Env:COMPUTERNAME
    $Servers = $Servers | Where-Object State -like "Online"
    foreach ($SingleServer in $Servers) {
        if ($SingleServer.OwnerNode -like $Env:COMPUTERNAME) {
            Write-Log -Source $EventSourceName -EventID 3002 -EntryType Info -Message "VM $SingleServer is being moved"
            Move-ClusterVirtualMachineRole -Name $SingleServer.OwnerGroup -MigrationType Live 
        }
    }
}

function Move_VMs_Back {
    $Servers = Get-ClusterResource | Where-Object { $_.ResourceType -like "Virtual Machine" }
    $Servers = $Servers | Where-Object State -like "Online"
    foreach ($SingleServer in $Servers) {
        $PreferredHost = $PreferredHosts | Where-Object ClusterObject -Match $SingleServer.OwnerGroup
        $PreferredHost = $PreferredHost.OwnerNodes[0].Name
        if ($SingleServer.OwnerNode.Name -notlike $PreferredHost) {
            Write-Log -Source $EventSourceName -EventID 3002 -EntryType Info -Message "VM $SingleServer is being moved back"
            Move-ClusterVirtualMachineRole -Name $SingleServer.OwnerGroup -Node $PreferredHost -MigrationType Live
        }
    }
}

function Set_Preferred_Owner {
    foreach ($PreferredHost in $PreferredHosts) {
        if (!$PreferredHost.OwnerNodes) {
            $SingleServer = Get-ClusterResource | Where-Object { $_.ResourceType -like "Virtual Machine" } | Where-Object OwnerGroup -Like $PreferredHost.ClusterObject
            Set-ClusterOwnerNode -Group $SingleServer.OwnerGroup -Owners $SingleServer.OwnerNode.Name
        }
    }
}

function Reboot_HV {
    $IsKeyPresent = Test-Path 'HKLM:\SOFTWARE\ShutdownScript'
    
    if (-not $IsKeyPresent) {
        try {
            if ($Running) {
                exit "Not all HyperV nodes are running"
            }

            if (!(Test-Path $ScriptRunning)) {
                New-Item -Name "scriptrunning.txt" -Path $DataStorage
                Set-Content $ScriptRunning -Value $Env:COMPUTERNAME
            } else {
                $Running = Get-Content $ScriptRunning
                if (!$Running) {
                    Set-Content $ScriptRunning -Value $Env:COMPUTERNAME    
                } else {
                    Write-Log -Source $EventSourceName -EventID 3002 -EntryType Error -Message "Script is still running on another HyperV"
                    exit
                }
            } 

            $Para = "-ExecutionPolicy unrestricted -NonInteractive -WindowStyle Hidden -NoLogo -NoProfile -NoExit -File " + '"' + $File + '"'
            $Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $Para
            $Option = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -WakeToRun
            $Trigger = New-JobTrigger -AtStartUp -RandomDelay (New-TimeSpan -Minutes 5)
            Register-ScheduledTask -TaskName RebootHVResumeJob -Action $Action -Trigger $Trigger -Settings $Option -RunLevel Highest -User "System"
     
            New-Item -Path HKLM:\SOFTWARE\ -Name ShutdownScript -Force
            
            for ($I = 0; $I -lt 5; $I++) {
                Move_VMs
                $VMs = Get-VM | Where-Object State -like "Running"
                $Servers = Get-ClusterResource | Where-Object { $_.ResourceType -like "Virtual Machine" }
                $Servers = $Servers | Where-Object OwnerNode -like $Env:COMPUTERNAME
                $Servers = $Servers | Where-Object State -like "Online"
                if (!$Servers) {
                    foreach ($VM in $VMs.Name) {
                        Stop-VM -Name $VM
                        Start-Sleep -Seconds 30
                    }
                    $VMs = Get-VM | Where-Object State -like "Running"
                    if ($null -eq $VMs) {
                        $I = 5
                    }
                }
            } 
            if ($null -ne $VMs) {
                Write-Log -Source $EventSourceName -EventID 3002 -EntryType Error -Message "Tried to move all VMs 5 times, but some are still running. Exiting!"
                Move_VMs_Back
                Exit "VMs couldn't be moved."
            }
            Suspend-ClusterNode -Name $Env:COMPUTERNAME
            Start-Sleep -s 3

            $Comment = "Hyper V Reboot for Smart Updates"
            $Reason = "P"
            $Major = 0
            $Minor = 0
            $Time = 1
            $PatchRun = "C:\Program Files (x86)\Server-Eye\triggerPatchRun.cmd"
            $FileToRunPath = "C:\WINDOWS\system32\shutdown.exe"
            $Argument = '/r /t {0} /c "{1}" /d {2}:{3}:{4}' -f $Time, $Comment, $Reason, $Major, $Minor
            $StartProcessParams = @{
                FilePath     = $FileToRunPath
                ArgumentList = $Argument       
                NoNewWindow  = $true
            }
            Write-Log -Source $EventSourceName -EventID 3002 -EntryType Info -Message "Starting Smart Updates"
            Start-Process $PatchRun -ArgumentList "force" -Wait
            Start-Process @StartProcessParams  
        }
        catch {
            Move_VMs_Back
            Write-Log -Source $EventSourceName -EventID 3002 -EntryType Error -Message "Something went wrong $_ "
        }
    } else {
        Resume-ClusterNode -Name $Env:COMPUTERNAME
        Start-Sleep -Seconds 60
        Move_VMs_Back
        Set-Content $ScriptRunning -Value $null
        Remove-Item -Path HKLM:\SOFTWARE\ShutdownScript -Recurse
        Unregister-ScheduledTask -TaskName RebootHVResumeJob -Confirm:$False
        Write-Log -Source $EventSourceName -EventID 3002 -EntryType Info -Message "Script finished"
    }
}
#endregion

#region Main execution
Set_Preferred_Owner
$PreferredHosts = Get-ClusterGroup | Get-ClusterOwnerNode
Reboot_HV

if (Test-Path "C:\ProgramData\ServerEye3\logs\SmartUpdates.Clusterrestart.log") {
    Remove-Item "C:\ProgramData\ServerEye3\logs\SmartUpdates.Clusterrestart.log" -Force
}
Rename-Item -Path "C:\ProgramData\ServerEye3\logs\SmartUpdates.Clusterrestart.temp" -NewName "C:\ProgramData\ServerEye3\logs\SmartUpdates.Clusterrestart.log"
#endregion
