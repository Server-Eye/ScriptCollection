<#
    .SYNOPSIS
    Shuts down all currently running VM's on this Hypervisor, restarts the Hypervisor, and starts the VM's again in opposite order.
    
    .DESCRIPTION
    The script will shut down all running VM's on the Hypervisor in the order provided by an accompanying .csv file.
    Afterwards, the Hypervisor will be rebooted and the VM's will be started again in the opposite order they were shut down.
    The script will shut down the VM's gracefully and provides a shutdown reason to the OS. New or deleted VM's are respected.
    See this article for further information:
    https://servereye.freshdesk.com/support/solutions/articles/14000138445-anleitung-automatische-hyper-v-reboots-für-smart-updates-mit-script

    .PARAMETER timeInMinutes
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
    [Parameter(Mandatory=$false)][int]$timeInMinutes = 30
)

# Path to the csv file
$csvPath = "C:\vms.csv"

function Reboot-HV {
    $Servers = Import-Csv $csvPath
    # Sort by priority to shutdown
    $Servers = $Servers | Sort-Object { [int]$_.Prio } -Descending
    
    # Shut down VMs array
    $ShutdownList = @()

    # Setting up switch case ($False=shutdown,$True=start)
    $B = Test-Path 'HKLM:\SOFTWARE\ShutdownScript'

    switch ($B) {
        $False {
            foreach ($Server in $Servers) {
                Stop-VM -Name $Server.Name -Force
        
                $i = 0
                # Loop until VM is off or max shutdown time is reached
                while ((Get-VM -Name $Server.Name).State -ne "Off" -and $i -lt $timeInMinutes * 4) {
                    Start-Sleep -Seconds 15
                    $i++
                }

                # If VM is off, add it to shutdown list
                if ((Get-VM -Name $Server.Name).State -eq "Off") {
                    $ShutdownList += $Server.Name
                }

                # Forcefully stop the VM if it is still running $timeInMinutes minutes after starting shutdown
                if (-Not ($ShutdownList -Contains $Server.Name)) {
                    Stop-VM -Name $Server.Name -TurnOff
                }
            }
            # Add and register scheduled task
            $Para = "-ExecutionPolicy unrestricted -NonInteractive -WindowStyle Hidden -NoLogo -NoProfile -NoExit -File '$CurrentScriptPath'"
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
            $timeInMinutes = 1
            $PatchRun = "C:\Program Files (x86)\Server-Eye\triggerPatchRun.cmd"
            $FileToRunPath = "C:\WINDOWS\system32\shutdown.exe"
            $Argument = '/r /t {0} /c "{1}" /d {2}:{3}:{4}' -f $timeInMinutes, $Comment, $Reason, $Major, $Minor
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
            $RunningVMs = @()

            foreach ($Server in $Servers) {
                # Boot VM
                Start-VM -Name $Server.Name

                $i = 0
                # Loop until VM is up or max boot time is reached
                while ((Get-VM -Name $Server.Name).State -ne "Running" -and $i -lt 61) {
                    Start-Sleep -Seconds 15
                    $i++
                }

                # If VM is up, add it to $RunningVMs
                if ((Get-VM -Name $Server.Name).State -eq "Running") {
                    $RunningVMs += $Server.Name
                    # Wait 120sec after successful boot
                    Start-Sleep -Seconds 120
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
    $Servers = Import-Csv $csvPath
    $VmPrio = 10
    
    # Names of currently active VMs
    $Cav = (Get-VM | Where-Object { $_.State -eq 'Running' }).Name

    foreach ($Vm in $Servers) {
        if(!($Cav.Contains($Vm.Name))) {
            # Delete inactive VM from CSV
            $Servers | Where-Object { $_.Name -NotLike $Vm.Name } | Export-Csv $csvPath -NoTypeInformation
            $Servers = Import-Csv $csvPath
        }
    }

    # Name of servers in $Servers
    $ServerNames = @()
    foreach($N in $Servers){ $ServerNames += $N.Name }
    
    foreach ($Vm in $Cav) {
        if(!($ServerNames.Contains($Vm))) {
            # Add new VM to list with highest prio
            $NewLineVM = "{0},{1}" -f $Vm, $VmPrio
            $NewLineVM | Add-Content -Path $csvPath
            $Servers = Import-Csv $csvPath
        }
    }
}

# Function to create vms.csv if not existent (does only run once)(all prios are set to 10)
function Create-CSV {
    $ActiveVms = Get-VM | Where-Object { $_.State -eq 'Running' }
    New-Item $csvPath -ItemType File
    Set-Content $csvPath 'Name,Prio'
    $Prio = 10
    foreach($ActiveVm in $ActiveVms) {
        $NewLineVM = "{0},{1}" -f $ActiveVm.Name, $Prio
        $NewLineVM | Add-Content -Path $csvPath
    }
}

function Replace-QuotesAndRows {
    $Result = Get-Content -Path $csvPath
    $Result = foreach ($line in $Result) {
        $line = $line.Replace('"', "")
        if ($line -ne "") {
            $line = $line.Trim()
        }
        $line
    }
    $Result | Set-Content $csvPath
}

$CurrentScriptPath = $MyInvocation.MyCommand.Path

# START
if(!(Test-Path $csvPath)) {
    Create-CSV
    exit
}
if(!(Test-Path HKLM:\SOFTWARE\ShutdownScript)) {
    Check-For-New-VM
}

Replace-QuotesAndRows
Reboot-HV