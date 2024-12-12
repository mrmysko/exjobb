[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,}$")]
    [string]$DomainName,
    
    [Parameter(Mandatory = $true)]
    [string]$SafeModeAdministratorPassword,
    
    [Parameter(Mandatory = $false)]
    [switch]$DHCP
)

# Validate domain name format
if ($DomainName -notmatch "\.") {
    throw "Domain name must include a top-level domain (e.g., 'domain.com')"
}

# Set timezone to Stockholm
Set-TimeZone -Id "W. Europe Standard Time"

# Install AD DS role
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Download Ubuntu policy files since we're creating a new domain
$currentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$admxUrl = "https://raw.githubusercontent.com/ubuntu/adsys/refs/heads/main/policies/Ubuntu/all/Ubuntu.admx"
$admlUrl = "https://raw.githubusercontent.com/ubuntu/adsys/refs/heads/main/policies/Ubuntu/all/Ubuntu.adml"

try {
    Invoke-WebRequest -Uri $admxUrl -OutFile "$currentDir\Ubuntu.admx"
    Invoke-WebRequest -Uri $admlUrl -OutFile "$currentDir\Ubuntu.adml"
}
catch {
    Write-Error "Failed to download Ubuntu policy files: $_"
    exit 1
}

# Create scheduled task for DHCP installation if requested
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

# Create scheduled task for new forest setup operations
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$setupAction = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"
    Start-Sleep -Seconds 60;
    
    # Setup reverse lookup zone
    `$ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.InterfaceAlias -notmatch 'Loopback' -and `$_.IPAddress -notmatch '^169' } | Select-Object -First 1).IPAddress
    if (`$ipAddress) {
        `$networkId = `$ipAddress.Split('.')[0..2] -join '.'
        Add-DnsServerPrimaryZone -NetworkID `"`$networkId.0/24`" -ReplicationScope 'Domain' -DynamicUpdate 'Secure'
    }

    # Copy PolicyDefinitions
    `$destinationPath = 'C:\Windows\SYSVOL\sysvol\$DomainName\Policies\PolicyDefinitions'
    `$scriptDir = '$scriptDir'
    
    if (!(Test-Path -Path `$destinationPath)) {
        New-Item -ItemType Directory -Path `$destinationPath -Force
        Copy-Item -Path 'C:\Windows\PolicyDefinitions\*' -Destination `$destinationPath -Recurse -Force
        
        if (Test-Path -Path `"`$scriptDir\Ubuntu.admx`") {
            Copy-Item -Path `"`$scriptDir\Ubuntu.admx`" -Destination `"`$destinationPath\Ubuntu.admx`" -Force
        }
        
        `$enUsPath = Join-Path `$destinationPath 'en-US'
        if (!(Test-Path -Path `$enUsPath)) {
            New-Item -ItemType Directory -Path `$enUsPath -Force
        }
        if (Test-Path -Path `"`$scriptDir\Ubuntu.adml`") {
            Copy-Item -Path `"`$scriptDir\Ubuntu.adml`" -Destination `"`$enUsPath\Ubuntu.adml`" -Force
        }
    }
    Unregister-ScheduledTask -TaskName NewForestSetup -Confirm:`$false
`""
Register-ScheduledTask -TaskName "NewForestSetup" -Action $setupAction -User "SYSTEM" -RunLevel Highest -Trigger (New-ScheduledTaskTrigger -AtStartup)

# Install new forest
Install-ADDSForest -InstallDns -DomainName $DomainName -SafeModeAdministratorPassword (ConvertTo-SecureString -AsPlainText $SafeModeAdministratorPassword -Force) -Confirm:$false -Force

# Sync time after ADDS Setup
w32tm /config /syncfromflags:DOMHIER /update