# Zabbix Agent - UserParameter - Zabbix Windows Service Monitor - Setup script
# ps_App_ZabbixAgent_ServiceMonitor_DiscoverItem.ps1
# MVogwell - Sept 2018
# Version 1
#
# Purpose: Discover services set to auto start but currently stopped. This information can then be added to the Local Exclusions file (overwritten not append)

[CmdletBinding()]
param (
    [Parameter(Mandatory=$False)][string]$InstallerFilesLocation = $PSScriptRoot,
    [Parameter(Mandatory=$False)][string]$ZabbixAgentServiceMonitorRoot = "C:\Zabbix\ZabbixServerMonitor"
)

Function ps_Function_CheckRunningAsAdmin {

    # Constructor
    [bool]$bRunningAsAdmin = $False

    Try {
        # Attempt to check if the current powershell session is being run with admin rights
        # System.Security.Principal.WindowsIdentity -- https://msdn.microsoft.com/en-us/library/system.security.principal.windowsidentity(v=vs.110).aspx
        # Info on Well Known Security Identifiers in Windows: https://support.microsoft.com/en-gb/help/243330/well-known-security-identifiers-in-windows-operating-systems

        write-verbose "ps_Function_CheckRunningAsAdmin :: Checking for admin rights"
        $bRunningAsAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
    }
    Catch {
        $bRunningAsAdmin = $False
        write-verbose "ps_Function_CheckRunningAsAdmin :: ERROR Checking for admin rights in current session"
        write-verbose "ps_Function_CheckRunningAsAdmin :: Error: $($Error[0].Exception)"
    }
    Finally {}

    write-verbose "ps_Function_CheckRunningAsAdmin :: Result :: $bRunningAsAdmin"

    # Return result from function
    return $bRunningAsAdmin
}

$ErrorActionPreference = "Stop"

# Setup key file locations:
$LocalExclusionsFilePath = $ZabbixAgentServiceMonitorRoot + "\ZabbizAgent_ServiceMonitor_LocalExclusions.dat"       # Set the path of the ZabbizAgent_ServiceMonitor_LocalExclusions.dat file
$GlobalExlucisionsFilePath = $ZabbixAgentServiceMonitorRoot + "\ZabbizAgent_ServiceMonitor_GlobalExclusions.dat"
$DiscoverItemScript = $ZabbixAgentServiceMonitorRoot + "\ps_App_ZabbixAgent_ServiceMonitor_DiscoverItem.ps1"        # This will be used in the zabbix agent config
$GetItemStateScript = $ZabbixAgentServiceMonitorRoot + "\ps_App_ZabbixAgent_ServiceMonitor_GetItemState.ps1"        # This will be used in the zabbix agent config

write-host "`n#####################################################################################" -fore green
write-host "#" -fore green
write-host "# Zabbix Agent Service Monitor Setup - MVogwell - v1" -fore Green
write-host "#" -fore green
Write-Host "# Installing the zabbix agent monitor scripts to $ZabbixAgentServiceMonitorRoot" -fore Green
Write-Host "# Source files location: $InstallerFilesLocation " -fore Green
write-host "#" -fore green
write-host "##################################################################################### `n" -fore green

$bRunningAsAdmin = ps_Function_CheckRunningAsAdmin

If($bRunningAsAdmin -eq $True) {

    write-host "Copying the scripts to $ZabbixAgentServiceMonitorRoot" -fore Yellow
    $bCreateFolderSuccess = $True

    Try {
        if(Test-Path ($ZabbixAgentServiceMonitorRoot)) {
            write-host "... Folder already exists. Using existing folder" -fore Green
        }
        Else {
            New-Item $ZabbixAgentServiceMonitorRoot -ItemType Directory -Force | out-null
            write-host "... Created folder" -fore green
        }
    }
    Catch  {
        $bCreateFolderSuccess = $False
        write-host "... Unable to create folder $ZabbixAgentServiceMonitorRoot" -fore Cyan
        Write-Host "... Check you have permission to create the folder and try again`n`n" -fore cyan
    }

    If($bCreateFolderSuccess) {    # Attempt to copy the script files to the new location
        $bCopyFilesSuccess = $True
        Try {
            $SourceFiles = $InstallerFilesLocation + "\*.*"
            Copy-Item $SourceFiles $ZabbixAgentServiceMonitorRoot -Force
        }
        Catch {
            $bCopyFilesSuccess = $False
            write-host "... It has not been possible to copy the files" -fore Cyan
            write-host "... Source: $Root" -fore cyan
            Write-Host "... Destination: $Dest" -fore cyan
            write-host "Please check the paths and re-run this installer script`n`n" -fore cyan
        }
    }

    If ($bCopyFilesSuccess) {
        # Extract the services
        write-host "`nEnumerating services set to auto start with status as 'Stopped'" -fore yellow
        $bGetServicesSuccess = $True

        Try {
            $StoppedServices = get-service | Where {($_.StartType -eq "Automatic") -and ($_.Status -ne "Running")} | Select Name, StartType, Status, DisplayName
        }
        Catch {
            $bGetServicesSuccess = $False
            write-host "... It has not been possible to enuerate the services! " -fore Red
            write-host "... The script will not continue and will not update $LocalExclusionsFilePath `n" -fore red
            # Exit
        }

        If($bGetServicesSuccess) {      # Only continue if it was possible to enumerate the services
            If($StoppedServices.Count -gt 0) {
                $bLogFileCreated = $True

                Try {
                    New-Item $LocalExclusionsFilePath -ItemType "File" -Force | out-null        # Overwrite any existing local service exclusion files
                }
                Catch {
                    $bLogFileCreated = $False
                    write-host "... Unable to create local exlusions file file $LocalExclusionsFilePath ." -fore cyan
                }

                If ($bLogFileCreated) {
                    Try {
                        $arrGlobalExclusions = Get-Content $GlobalExlucisionsFilePath
                    }
                    Catch {
                        $arrGlobalExclusions = @()
                    }

                    ForEach ($StoppedService in $StoppedServices) {                                         # Add each of the excluded services to the Local exclusions file
                        If($arrGlobalExclusions -match $StoppedService.Name) {
                            write-host "... Service $($StoppedService.DisplayName) is in the Global Excluded Services list" -fore DarkMagenta
                        }
                        Else {
                            Try {
                                add-content $LocalExclusionsFilePath -value $($StoppedService.DisplayName)
                                write-host "... Successfully added $($StoppedService.DisplayName)" -fore green
                            }
                            Catch {
                                write-host "...  Failed to add $($StoppedService.DisplayName)" -fore cyan
                            }
                        }
                    }
                }
            }
            Else {
                write-host "No stopped services have been found" -fore yellow
                write-host "No exclusions have been set in $LocalExclusionsFilePath `n`n" -fore yellow
            }
        }


        write-host "`n`nAppending the required agent settings" -fore Yellow
        write-host "... Retrieving the zabbix config path" -fore Green

        # Attempt to extract the zabbix config path from the service pathName property. If fails returns string of zero length
        $ZabbixConfigPath = ""
        Try {
            $zabbixAgentPath = Get-WmiObject win32_service | ?{$_.Name -like '*zabbix agent'} | select PathName
            $arrZabbixServiceElements = ($zabbixAgentPath.PathName).Split(" ")
            $i = 0
            ForEach ($arrZabbixServiceElement in $arrZabbixServiceElements) {
                if($arrZabbixServiceElement -match "config") {
                    $ZabbixConfigPath = $arrZabbixServiceElements[$i+1]
                }
                $i ++
            }

            $ZabbixConfigPath = $ZabbixConfigPath.replace("""","")
            write-host "... Attempting to use config path $ZabbixConfigPath" -fore green
        }
        Catch {
            $ZabbixConfigPath = ""
        }

        $sAdditionConfigZabbixServiceDiscovery = "UserParameter=winservice.discovery,powershell -NoProfile -ExecutionPolicy Bypass -File `"" + $DiscoverItemScript + "`""
        $sAdditionConfigZabbixServiceGetState = "UserParameter=winservice.state[*],powershell -NoProfile -ExecutionPolicy Bypass -File `"" + $GetItemStateScript +  "`" `"`$1`""

        If(Test-Path ($ZabbixConfigPath)) {

            Try {
                Write-Host "... Checking contents of $ZabbixConfigPath" -fore green
                $arrZabbixConfig = Get-Content "$ZabbixConfigPath"

                if(!($arrZabbixConfig -match "winservice")) {
                    add-content $ZabbixConfigPath -Value $sAdditionConfigZabbixServiceDiscovery
                    add-content $ZabbixConfigPath -Value $sAdditionConfigZabbixServiceGetState
                    Write-Host "... Successfully added the new config to the zabbix config file" -fore green
                }
                Else {
                    write-host "... The config already contains UserParamters for winservice. " -fore DarkMagenta
                    write-host "    Remove any lines starting 'UserParameter=winservice.' and re-run this script`n" -fore DarkMagenta
                }
            }
            Catch {
                $error[0]

                write-host "... It was not possible to retrieve the zabbix agent config file location " -fore Cyan
                Write-Host "... Please add the following lines to the zabbix agent config file: `n" -fore Cyan

                write-host "$sAdditionConfigZabbixServiceDiscovery `n" -fore Yellow
                write-host "$sAdditionConfigZabbixServiceGetState `n" -fore Yellow
            }

            Restart-Service "Zabbix Agent"
        }
        Else {
            write-host "... It was not possible to retrieve the zabbix agent config file location " -fore Cyan
            Write-Host "... Please add the following lines to the zabbix agent config file: `n" -fore Cyan

            write-host "$sAdditionConfigZabbixServiceDiscovery `n" -fore Yellow
            write-host "$sAdditionConfigZabbixServiceGetState " -fore Yellow
        }
    }
    Write-Host "`nFinished`n`n" -fore green
}
Else {
    write-host "You MUST be running powershell elevated as an admin to run this script!" -fore Red
    write-host "The script will now exit!`n" -fore red
}

