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
    PS C:\> .\Reboot-VMsAndHV-SU.ps1 -timeInMinutes 60
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
    $boolShutdownScript = Test-Path 'HKLM:\SOFTWARE\ShutdownScript'

    switch ($boolShutdownScript) {
        $False {
            foreach ($Server in $Servers) {
                Stop-VM -Name $Server.Name -Force
                
                # Loop until VM is off or max shutdown time is reached
                for ($i = 0; $i -lt ($timeInMinutes * 4) -and (Get-VM -Name $Server.Name).State -ne "Off"; $i++) {
                    Start-Sleep -Seconds 15
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
            $Para = "-ExecutionPolicy unrestricted -NonInteractive -WindowStyle Hidden -NoLogo -NoProfile -NoExit -File `"$CurrentScriptPath`""
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

                # Loop until VM is up or max boot time is reached
                for ($i = 0; $i -lt 61 -and (Get-VM -Name $Server.Name).State -ne "Running"; $i++) {
                    Start-Sleep -Seconds 15
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
    foreach($N in $Servers) {
        $ServerNames += $N.Name
    }
    
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
# SIG # Begin signature block
# MIIUrAYJKoZIhvcNAQcCoIIUnTCCFJkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBAAUJJz7ubJ8Un
# 2+MdJx8K4FD2ZsyBJMSOEx2bI8gLUaCCEWcwggVvMIIEV6ADAgECAhBI/JO0YFWU
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
# KoZIhvcNAQkEMSIEIN6DfhNHmH2KGdcTB2A+m7uAT4GimncsarQw76T2dxvYMA0G
# CSqGSIb3DQEBAQUABIIBgHYl/c5LZBKJbSlyLCwxLoEpbyYK7AG9BHaMkz/S6cqI
# kzyVb4AYpo97LA1nBpYENfCDxlLvTkGVAcujEpIEjKeXDaHfo310LlXNL4G3z55I
# eI6ZzsdJxzHNpRYd01YtxofGbc03Wvv3ebEu49vPJs8mISxqPl4BGTHh2Ppab9iU
# VveyxMhwseyeWvu6P37FaFzW+OZrdflNTedBe9U5430vXua7FkIcv4+rrpjrvQKp
# DQ/6YKPHb2NrzM6fZnV/f5u8F9+y7C9mTPDY/CP/83u+2VoTn+q7tiErfpPfuZFS
# 9EKUne4pQRwvpgIl1D/qudxzwF/31yHV2tH/eec8YehokrikJ++UDv5cn0pxlRb/
# q3d3cOqUbRejOQg8vt77QSM8k01RsxNEizyX2t/n88G6ETolB5ZGycdYZiXg5Am0
# W3JsxKe+uNYd2HeulG0+AdkBTHjnSWX0J1aQbVXivuNifj7waCEf3lxcLFlTp+8k
# WBL+7UQHYeMf0wkYByayVQ==
# SIG # End signature block
