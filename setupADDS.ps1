[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName,
    [Parameter(Mandatory = $false)]
    [switch]$DHCP
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
    
    if ($DHCP) {
        Install-WindowsFeature DHCP -IncludeManagementTools
        Add-DhcpServerSecurityGroup
        
        $computerName = $env:COMPUTERNAME
        $ipAddress = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias Ethernet).IPAddress
        $fqdn = "$computerName.$DomainName"
        
        Add-DhcpServerInDC -DnsName $fqdn -IPAddress $ipAddress
        Set-ItemProperty -Path registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager\Roles\12 -Name ConfigurationState -Value 2
    }
}

# Sync time after ADDS Setup
w32tm /config /syncfromflags:DOMHIER /update