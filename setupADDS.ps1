[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,}$")]
    [string]$DomainName,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SafeModeAdministratorPassword,
    [Parameter(Mandatory = $false)]
    [switch]$DHCP
)

# Validate domain name format
if ($DomainName -notmatch "\.") {
    throw "Domain name must include a top-level domain (e.g., 'domain.com')"
}

# Convert the password to secure string
$securePassword = ConvertTo-SecureString $SafeModeAdministratorPassword -AsPlainText -Force

# Set timezone to Stockholm
Set-TimeZone -Id "W. Europe Standard Time"

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Import-Module ActiveDirectory

# If domain controller already exists, join forest.
try {
    if (Get-ADDomainController -ErrorAction Stop) {
        Install-ADDSDomainController -InstallDns -DomainName $DomainName -SafeModeAdministratorPassword $securePassword -Confirm:$false -Force
    }
}
# Else create forest and configure DHCP after restart
catch {
    # Download Ubuntu policy files since we're creating a new domain
    $currentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $admxUrl = "https://raw.githubusercontent.com/ubuntu/adsys/refs/heads/main/policies/Ubuntu/all/Ubuntu.admx"
    $admlUrl = "https://raw.githubusercontent.com/ubuntu/adsys/refs/heads/main/policies/Ubuntu/all/Ubuntu.adml"

    try {
        Invoke-WebRequest -Uri $admxUrl -OutFile "$currentDir\Ubuntu.admx"
        Invoke-WebRequest -Uri $admlUrl -OutFile "$currentDir\Ubuntu.adml"
    } catch {
        Write-Error "Failed to download Ubuntu policy files: $_"
        exit 1
    }

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
    
    # Create scheduled task for new forest setup operations (PolicyDefinitions and reverse DNS)
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $setupAction = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"
        Start-Sleep -Seconds 60;
        
        # Setup reverse lookup zone for new forest
        `$ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.InterfaceAlias -notmatch 'Loopback' -and `$_.IPAddress -notmatch '^169' } | Select-Object -First 1).IPAddress
        if (`$ipAddress) {
            `$networkId = `$ipAddress.Split('.')[0..2] -join '.'
            try {
                Add-DnsServerPrimaryZone -NetworkID `"`$networkId.0/24`" -ReplicationScope 'Domain' -DynamicUpdate 'Secure'
                Write-Host `"Successfully created reverse lookup zone for `$networkId.0/24`"
            } catch {
                Write-Warning `"Failed to create reverse lookup zone: `$_`"
            }
        } else {
            Write-Warning `"No suitable IP address found for reverse zone creation`"
        }

        # Copy PolicyDefinitions
        `$destinationPath = 'C:\Windows\SYSVOL\sysvol\$DomainName\Policies\PolicyDefinitions';
        `$scriptDir = '$scriptDir';
        
        if (!(Test-Path -Path `$destinationPath)) {
            # Create main PolicyDefinitions directory and copy all default files
            New-Item -ItemType Directory -Path `$destinationPath -Force;
            Copy-Item -Path 'C:\Windows\PolicyDefinitions\*' -Destination `$destinationPath -Recurse -Force;
            
            # Copy Ubuntu ADMX file
            if (Test-Path -Path `"`$scriptDir\Ubuntu.admx`") {
                Copy-Item -Path `"`$scriptDir\Ubuntu.admx`" -Destination `"`$destinationPath\Ubuntu.admx`" -Force;
            }
            
            # Create en-US directory if it doesn't exist and copy Ubuntu ADML file
            `$enUsPath = Join-Path `$destinationPath 'en-US';
            if (!(Test-Path -Path `$enUsPath)) {
                New-Item -ItemType Directory -Path `$enUsPath -Force;
            }
            if (Test-Path -Path `"`$scriptDir\Ubuntu.adml`") {
                Copy-Item -Path `"`$scriptDir\Ubuntu.adml`" -Destination `"`$enUsPath\Ubuntu.adml`" -Force;
            }
        }
        Unregister-ScheduledTask -TaskName NewForestSetup -Confirm:`$false
    `""
    Register-ScheduledTask -TaskName "NewForestSetup" -Action $setupAction -User "SYSTEM" -RunLevel Highest -Trigger (New-ScheduledTaskTrigger -AtStartup)
    
    Install-ADDSForest -InstallDns -DomainName $DomainName -SafeModeAdministratorPassword $securePassword -Confirm:$false -Force
}

# Sync time after ADDS Setup
w32tm /config /syncfromflags:DOMHIER /update