# Script for creating or joining a domain.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName
)

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