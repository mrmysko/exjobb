# Script for creating or joining a domain.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName
)

# Set timezone to Stockholm
Set-TimeZone -Id "W. Europe Standard Time"

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Import-Module ActiveDirectory

# If domain controller already exists, join forest.
try {
    if (Get-ADDomainController -ErrorAction Stop) {
        Install-ADDSDomainController -InstallDns -DomainName $DomainName
    }
}
# Else create forest.
catch {
    Install-ADDSForest -InstallDns -DomainName $DomainName
}

# Sync time after ADDS Setup
w32tm /config /syncfromflags:DOMHIER /update