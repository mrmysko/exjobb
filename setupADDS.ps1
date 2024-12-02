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
# Else create forest and configure DHCP after restart
catch {
    # Create scheduled task to install DHCP after restart if parameter is set
    if ($DHCP) {
        $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -Command "
            Start-Sleep -Seconds 60;
            Install-WindowsFeature DHCP -IncludeManagementTools;
            Add-DhcpServerSecurityGroup;
            Set-ItemProperty -Path registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager\Roles\12 -Name ConfigurationState -Value 2;
            Unregister-ScheduledTask -TaskName InstallDHCP -Confirm:$false
        "'
        Register-ScheduledTask -TaskName "InstallDHCP" -Action $action -User "SYSTEM" -RunLevel Highest -Trigger (New-ScheduledTaskTrigger -AtStartup)
    }
    
    Install-ADDSForest -InstallDns -DomainName $DomainName
}

# Sync time after ADDS Setup
w32tm /config /syncfromflags:DOMHIER /update