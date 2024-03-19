<#
    .SYNOPSIS
    Shuts down all currently running VM's on this Hypervisor, restarts the Hypervisor, and starts the VM's again in opposite order.
    
    .DESCRIPTION
    The script will shut down all running VM's on the Hypervisor in the order provided by an accompanying .csv file.
    Afterwards, the Hypervisor will be rebooted and the VM's will be started again in the opposite order they were shut down.
    The script will shut down the VM's gracefully and provides a shutdown reason to the OS. New or deleted VM's are respected.
    See this article for further information:
    https://servereye.freshdesk.com/support/solutions/articles/14000138445-anleitung-automatische-hyper-v-reboots-für-smart-updates-mit-script

    .PARAMETER Time
    Time in minutes that a VM can take to shut down before it is forcefully stopped.
    The default time is 30 minutes.
	
    .NOTES
    Author  : Nico Krämer, Modified by Leon Zewe - servereye
    Version : 1.1

    .EXAMPLE 
    Execute the script one time to create the .csv file (while making sure no file has been created yet):
    PS C:\> .\Reboot-VMsAndHV-SU.ps1
    Execute the script again after making the neccessary changes to the .csv file. The maximum allowed shutdown time is set to 60 minutes in this example:
    PS C:\> .\Reboot-VMsAndHV-SU.ps1 -Time 60
#>

Param (
    [Parameter(Mandatory=$false)][int]$Time = 30
)

function Reboot-HV {
    $Servers = Import-Csv "C:\vms.csv"
    # Sort by priority to shutdown
    $Servers = $Servers | Sort-Object { [int]$_.Prio } -Descending
    
    # Shut down VMs array
    $Down = @()

    # Setting up switch case ($False=shutdown,$True=start)
    $B = Test-Path 'HKLM:\SOFTWARE\ShutdownScript'
    
    # Set max time to shutdown
    $T = $Time * 4 + 1 

    switch ($B) {
        $False {
            foreach ($Server in $Servers) {
                # Shut down VM
                Stop-VM -Name $Server.Name -Force
        
                # Loop $T times (eq. max. $Time minutes)
                for ($I = 1; $I -le $T; $I++){
                    # Check if VM is down, if true add it to $Down, else wait 15sec and check again
                    if ((Get-VM -Name $Server.Name).State -eq "Off"){
                        $Down += $Server.Name
                        Start-Sleep -Seconds 2
                        $I = $T + 1
                    } else {
                        Start-Sleep -Seconds 15 
                    }
                }
                # Forcefully stop the VM if its is still running $Time minutes after shutdown initiation
                if (!($Down -contains $Server.Name)){
                    Stop-VM -Name $Server.Name -TurnOff
                }
            }
            # Add and register scheduled task
            $Para = "-ExecutionPolicy unrestricted -NonInteractive -WindowStyle Hidden -NoLogo -NoProfile -NoExit -File " + '"' + $CurrentScriptPath + '"'
            $Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $Para
            $Option = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -WakeToRun
            $Trigger = New-JobTrigger -AtStartUp -RandomDelay (New-TimeSpan -Minutes 5)
            Register-ScheduledTask -TaskName RebootHVResumeJob -Action $Action -Trigger $Trigger -Settings $Option -RunLevel Highest -User "System"

            # Create regkey
            New-Item -Path HKLM:\SOFTWARE\ -Name ShutdownScript -Force
            
            # Wait 3sec then reboot
            Start-Sleep -Seconds 3

            # Reboot Hyper-V
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
                NoNewWindow  = $True
            }
            Start-Process $PatchRun -ArgumentList "force" -Wait
            Start-Process @StartProcessParams
        }
        $True {
            # Sort by priority to boot
            $Servers = $Servers | Sort-Object { [int]$_.Prio }
            
            # Running VMs array
            $Up = @()

            foreach ($Server in $Servers) {
        
                # Boot VM
                Start-VM -Name $Server.Name
        
                # Loop 60 times (eq. max. 15min)
                for ($I = 1; $I -le 61; $I++){
                    # Check if VM is up, if true add it to $Up, else wait 15sec and check again
                    if ((Get-VM -Name $Server.Name).State -eq "Running"){
                        $Up += $Server.Name
                        $I = 61
                        # Wait 120sec after successful boot
                        Start-Sleep -Seconds 120
                    } else {
                        Start-Sleep -Seconds 15 
                    }
                }
            }
            # Remove regkey
            Remove-Item -Path HKLM:\SOFTWARE\ShutdownScript -Recurse
            # Remove job 
            Unregister-ScheduledTask -TaskName RebootHVResumeJob -Confirm:$False
        }
    }
}

function Check-For-New-VM {
    # Import CSV
    $Servers = Import-Csv "C:\vms.csv"
    $VmPrio = 10
    
    # Names of currently active VMs
    $Cav = (Get-VM | Where-Object { $_.State -eq 'Running' }).Name

    foreach ($Vm in $Servers) {
        if(!($Cav.Contains($Vm.Name))){
            # Delete inactive VM from CSV
            $Servers | Where-Object { $_.Name -NotLike $Vm.Name } | Export-Csv "C:\vms.csv" -NoTypeInformation
            $Servers = Import-Csv "C:\vms.csv"
        }
    }

    # Name of servers in $Servers
    $ServerNames = @()
    foreach($N in $Servers){ $ServerNames += $N.Name }
    
    foreach ($Vm in $Cav) {
        if(!($ServerNames.Contains($Vm))){
            # Add new VM to list with highest prio
            $NewLineVM = "{0},{1}" -f $Vm, $VmPrio
            $NewLineVM | Add-Content -Path "C:\vms.csv"
            $Servers = Import-Csv "C:\vms.csv"
        }
    }
}

# Function to create vms.csv if not existent (does only run once)(all prios are set to 10)
function Create-CSV {
    $ActiveVms = Get-VM | Where-Object { $_.State -eq 'Running' }
    New-Item C:\vms.csv -ItemType File
    Set-Content C:\vms.csv 'Name,Prio'
    $Prio = 10
    foreach($ActiveVm in $ActiveVms) {
        $NewLineVM = "{0},{1}" -f $ActiveVm.Name, $Prio
        $NewLineVM | Add-Content -Path "C:\vms.csv" 
    }
}

function Replace-Quotes {
    $Result = Get-Content -Path "C:\vms.csv"
    $Result | ForEach-Object { $_ -replace '"', ""} | Set-Content "C:\vms.csv"
}

function Replace-Empty-Rows {
    $Result = Get-Content -Path "C:\vms.csv"
    $Result | ForEach-Object Trim | Where-Object Length -gt 0 | Set-Content "C:\vms.csv"
}

$CurrentScriptPath = $MyInvocation.MyCommand.Path

# START
if(!(Test-Path C:\vms.csv)) {
    Create-CSV
    exit
}
if(!(Test-Path HKLM:\SOFTWARE\ShutdownScript)) {
    Check-For-New-VM
}

Replace-Quotes
Replace-Empty-Rows
Reboot-HV