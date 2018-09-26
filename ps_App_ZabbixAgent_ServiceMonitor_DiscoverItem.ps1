# Zabbix Agent - UserParameter - Zabbix Windows Service Monitor - Service Discovery
# ps_App_ZabbixAgent_ServiceMonitor_DiscoverItem.ps1
# MVogwell - Sept 2018
# Version 1
#
# Purpose: Discover services set to auto start except those listed in a global or local expections list

$ErrorActionPreference = "Stop"

# File locations
$fGlobalExclusions = $PSScriptRoot + "\ZabbizAgent_ServiceMonitor_GlobalExclusions.dat"
$fLocalExclusions = $PSScriptRoot + "\ZabbizAgent_ServiceMonitor_LocalExclusions.dat"

# Start json block
write-output "{"
write-output " `"data`":[`n"

# Get a list of services set to start automatically
$bErrorGettingServices = $False
Try {
    $objSvc = get-service | where {($_.StartType -eq "Automatic")} | select Name, DisplayName
}
Catch {
    $bErrorGettingServices = $True
    $sOutput = $sOutput = "{ `"{#WINSERVICE}`" : `"Failed to extract services`" }"
    write-output $sOutput
}

if(!($bErrorGettingServices)) {
    # Create variable to hold all of the service exclusions
    $arrServiceExclusions = @()

    # Load global service exclusions
    Try {
        If(Test-Path($fGlobalExclusions)) { $arrGlobalExclusions = Get-Content $fGlobalExclusions }

        if($arrGlobalExclusions.count -gt 0) {
            $arrServiceExclusions += $arrGlobalExclusions
        }
    }
    Catch { }

    # Load local machine specific service exclusions
    Try {
        If(Test-Path($fLocalExclusions) ) { $arrLocalExclusions = Get-Content $fLocalExclusions }
        if($arrLocalExclusions.count -gt 0) {
            $arrServiceExclusions += $arrLocalExclusions
        }
    }
    Catch { }

    [int]$iServiceCountTotal = $objSvc.Count - 1
    [int]$iServiceCount = 0

    # Loop through the discovered services and put into json format
    ForEach ($Service in $objSvc) {

        # Check that the service name isn't on the exclusions list (Local and Global). If it is then the service won't be sent back to Zabbix for monitoring.
        If(!($arrServiceExclusions -contains $($Service.DisplayName))) {
            # If this iteration is not the last service then add a comm to the end
            if($iServiceCount -lt $iServiceCountTotal) {
                $sOutput = "{ `"{#WINSERVICE}`" : `"" + $($Service.DisplayName) + "`" },"
                write-output $sOutput
            }
            # And if this is the last iteration then don't print the comma
            elseif($iServiceCount -eq $iServiceCountTotal) {
                $sOutput = "{ `"{#WINSERVICE}`" : `"" + $($Service.DisplayName) + "`" }"
                write-output $sOutput
            }
        }

        # Increment the service so that the last iteration doesn't include the comma
        $iServiceCount ++
    }
}

# Add JSON Footer
write-output ""
write-output " ]"
write-output "}"

