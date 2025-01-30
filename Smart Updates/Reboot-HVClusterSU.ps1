# Get all VM in the Cluster
$Servers = Get-ClusterResource | Where-Object{$_.ResourceType -like "Virtual Machine"}
# Get all prefered HyperV Nodes in the Cluster
$preferedHosts=Get-ClusterGroup | Get-ClusterOwnerNode
$file = $MyInvocation.MyCommand.Path
# Check if Alle Clusternodes ere running and exit Skript if not all are running
$running=Get-Clusternode  | Where-Object State -NotContains "Up"


$EventSourceName = "ServerEye-Custom"
$script:_SilentOverride = $true
$script:_SilentEventlog = $true
if (Test-Path "C:\ProgramData\ServerEye3") {
    $_LogFilePath = "C:\ProgramData\ServerEye3\logs\smartUpdates.Clusterrestart.temp"
}else {
    $_LogFilePath = "C:\ProgramData\ServerEye\logs\smartUpdates.Clusterrestart.temp"
}

$datastorage=Get-ChildItem "C:\ClusterStorage"
$datastorage=$datastorage[0].FullName
$skriptrunning="$datastorage\skriptrunning.txt"

function Write-Log {
    <#
            .SYNOPSIS
                A swift logging function.
            
            .DESCRIPTION
                A simple way to produce logs in various formats.
                Log-Types:
                - Eventlog (Application --> ServerEyeDeployment)
                - LogFile (Includes timestamp, EntryType, EventID and Message)
                - Screen (Includes only the message)
            
            .PARAMETER Message
                The message to log.
            
            .PARAMETER Silent
                Whether anything should be written to host. Is controlled by the closest scoped $_SilentOverride variable, unless specified.
 
            .PARAMETER SilentEventlog
                Whether anything should be written to the Eventlog. Is controlled by the closest scoped $_SilentEventlog variable, unless specified.
            
            .PARAMETER ForegroundColor
                In what color messages should be written to the host.
                Ignored if silent is set to true.
            
            .PARAMETER NoNewLine
                Prevents Debug to host to move on to the next line.
                Ignored if silent is set to true.
            
            .PARAMETER EventID
                ID of the event as logged to both the eventlog as well as the logfile.
                Defaults to 1000
            
            .PARAMETER EntryType
                The type of event that is written.
                By default an information event is written.
            
            .PARAMETER LogFilePath
                The path to the file (including filename) that is written to.
                Is controlled by the closest scoped $_LogFilePath variable, unless specified.
                
        #>
    [CmdletBinding()]
    Param (
        [Parameter(Position = 0)]
        [string]
        $Message,
            
        [bool]
        $Silent = $_SilentOverride,
 
        [bool]
        $SilentEventlog = $_SilentEventlog,
        
        [System.ConsoleColor]
        $ForegroundColor,
            
        [switch]
        $NoNewLine,
            
        [Parameter(Position = 1)]
        [int]
        $EventID = 1000,
 
        [Parameter(Position = 1)]
        [string]
        $Source,
 
            
        [Parameter(Position = 3)]
        [System.Diagnostics.EventLogEntryType]
        $EntryType = ([System.Diagnostics.EventLogEntryType]::Information),
            
        [string]
        $LogFilePath = $_LogFilePath
    )
  
    # Log to Eventlog
    if (-not $SilentEventlog) {
        try { Write-EventLog -Message $message -LogName 'Application' -Source $Source -Category 0 -EventId $EventID -EntryType $EntryType -ErrorAction Stop }
        catch { }
    }
 
        
    # Log to File
    try { "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $EntryType $EventID - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop }
    catch { }
        
    # Write to screen
    if (-not $Silent) {
        $splat = @{ }
        $splat['Object'] = $Message
        if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $splat['ForegroundColor'] = $ForegroundColor }
        if ($PSBoundParameters.ContainsKey('NoNewLine')) { $splat['NoNewLine'] = $NoNewLine }
        Write-Output @splat
    }
 
}


function move_vms {
    $Servers = Get-ClusterResource | Where-Object{$_.ResourceType -like "Virtual Machine"}
    $server = $Servers| Where-Object Ownernode -like $env:computername
    $Servers = $Servers| Where-Object State -like "Online"
    foreach ($server in $servers){
        if ($server.OwnerNode -like $env:computername){
            Write-Log -Source $EventSourceName -EventID 3002 -EntryType Info -Message "VM $server wird verschoben"
            Move-ClusterVirtualMachineRole -Name $server.OwnerGroup -MigrationType Live 
        }
    }
}
function move_vms_back {
    $Servers = Get-ClusterResource | Where-Object{$_.ResourceType -like "Virtual Machine"}
    $Servers = $Servers| Where-Object State -like "Online"
    foreach ($server in $servers){
        $preferedHost=$preferedHosts |Where-Object ClusterObject -Match $Server.OwnerGroup
        $preferedHost=$preferedHost.OwnerNodes[0].Name #nimm immer den am meisten bevorzugten hyperv falls mehrere bevorzugt werden
        if ($Server.OwnerNode.Name -notlike $preferedHost){
            Write-Log -Source $EventSourceName -EventID 3002 -EntryType Info -Message "VM $server wird zurückgeschoben"
            Move-ClusterVirtualMachineRole -Name $Server.OwnerGroup -Node $preferedHost -MigrationType Live
        }
    }
}
function set_preferred_owner{
    foreach($preferedHost in $preferedHosts){
        if(!$preferedHost.OwnerNodes){
            $Server=Get-ClusterResource | Where-Object{$_.ResourceType -like "Virtual Machine"}|Where-Object OwnerGroup -Like $preferedHost.ClusterObject
            Set-ClusterOwnerNode -Group $server.OwnerGroup -Owners $Server.OwnerNode.Name
        }

        
    }

}
function Reboot_HV {
    #sort by priority to shutdown
 
    #setting up switch case ($false=shutdown,$true=start)
    $b = Test-Path 'HKLM:\SOFTWARE\ShutdownScript'
    
 
    switch ($b) {
        $false {
            try {
                If ($running){
                    exit "not all HyperV nodes are running"
                }

                if (!(Test-Path $skriptrunning)) {
                    New-Item -Name "skriptrunning.txt" -Path $datastorage
                    Set-Content $skriptrunning -Value $env:computername
                }else {
                    $running= Get-Content $skriptrunning
                    if (!$running) {
                        Set-Content $skriptrunning -Value $env:computername    
                    }else {
                        Write-Log -Source $EventSourceName -EventID 3002 -EntryType Error -Message "Skript läuft noch auf einem anderen HyperV"
                        exit
                    }
                } 
                #add and register scheduled task
                $para = "-ExecutionPolicy unrestricted -NonInteractive -WindowStyle Hidden -NoLogo -NoProfile -NoExit -File " + '"' + $file + '"'
                $Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $para
                $Option = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -WakeToRun
                $Trigger = New-JobTrigger -AtStartUp -RandomDelay (New-TimeSpan -Minutes 5)
                Register-ScheduledTask -TaskName RebootHVResumeJob -Action $Action -Trigger $Trigger -Settings $Option -RunLevel Highest -User "System"
     
                #create regkey
                New-Item -Path HKLM:\SOFTWARE\ -Name ShutdownScript -Force
                
                
                
                #loop for trying to move all vm to other hyperV
                $vms =get-vm |Where-Object State -like "Running"
                for ($i = 0; $i -lt 5; $i++) {
                    move_vms
                    $vms =get-vm |Where-Object State -like "Running"
                    $Servers = Get-ClusterResource | Where-Object{$_.ResourceType -like "Virtual Machine"}
                    $servers = $Servers| Where-Object Ownernode -like $env:computername
                    $Servers = $Servers| Where-Object State -like "Online"
                    if (!$servers) {
                        foreach($vm in $vms.Name){
                            stop-vm -Name $vm
                            Start-Sleep -Seconds 30
                        }
                        $vms =get-vm |Where-Object State -like "Running"
                        if ($null -eq $vms) {
                            $i=5
                        }

                        
                    }

                } 
                if ($null -ne $vms) {
                    Write-Log -Source $EventSourceName -EventID 3002 -EntryType Error -Message "5 mal erfolglos versucht alle VMs zu verschieben, abbruch"
                    move_vms_back
                    Exit "VMS konnten nicht verschoben werden"
                }
                Suspend-ClusterNode -Name $env:computername
                #wait 3sec then reboot
                Start-Sleep -s 3
                #Reboot Hyper-V
                $Comment = "Hyper V Reboot for Smart Updates"
                $reason = "P"
                $major = 0
                $minor = 0
                $Time = 1
                $patchrun = "C:\Program Files (x86)\Server-Eye\triggerPatchRun.cmd"
                $FileToRunpath = "C:\WINDOWS\system32\shutdown.exe"
                $argument = '/r /t {0} /c "{1}" /d {2}:{3}:{4}' -f $Time, $Comment, $reason, $major, $minor
                $startProcessParams = @{
                    FilePath     = $FileToRunpath
                    ArgumentList = $argument       
                    NoNewWindow  = $true
                }
                Write-Log -Source $EventSourceName -EventID 3002 -EntryType Info -Message "Starte Smartupdates"
                Start-Process $patchrun -ArgumentList "force" -Wait
                Start-Process @startProcessParams  
                
            }
            catch {
                move_vms_back
                Write-Log -Source $EventSourceName -EventID 3002 -EntryType Error -Message "Something went wrong $_ "
            }
            
        }
        $true {
            resume-ClusterNode -Name $env:computername

            Start-Sleep -Seconds 60
            move_vms_back
            Set-Content $skriptrunning -Value $null
            #remove regkey
            Remove-Item -Path HKLM:\SOFTWARE\ShutdownScript -Recurse
            #remove job 
            Unregister-ScheduledTask -TaskName RebootHVResumeJob -Confirm:$False
            Write-Log -Source $EventSourceName -EventID 3002 -EntryType Info -Message "Skript erfolgreich"
        }
    }
}


set_preferred_owner
$preferedHosts=Get-ClusterGroup | Get-ClusterOwnerNode
Reboot_HV

Test-Path ("C:\ProgramData\ServerEye3\logs\smartUpdates.Clusterrestart.log"){
    Remove-Item "C:\ProgramData\ServerEye3\logs\smartUpdates.Clusterrestart.log" -Force
}
Rename-Item -Path "C:\ProgramData\ServerEye3\logs\smartUpdates.Clusterrestart.temp" -NewName "C:\ProgramData\ServerEye3\logs\smartUpdates.Clusterrestart.log"