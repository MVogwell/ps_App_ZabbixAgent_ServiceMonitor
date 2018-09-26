# Zabbix Agent - UserParameter - Zabbix Windows Service Monitor - GetItemState
# MVogwell - Sept 2018
# Version 1
#
# Purpose: Enumerate services set to auto start except those listed in a global or local expections list

param( [string]$name = 0 )

$ErrorActionPreference = "Stop"

Try {
    $ServiceState = Get-Service $name
    Write-Output ($ServiceState.Status)
}
Catch {
    Write-Output "UnknownService"
}
