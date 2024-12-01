param(
    [Parameter(Mandatory = $true)]
    [int]$NumberOfTiers,
    
    [Parameter(Mandatory = $false)]
    [switch]$DisableDeleteProtection,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipGPO,
    
    [Parameter(Mandatory = $false)]
    [string]$GpoZipPath = ".\GPOs.zip",
    
    [Parameter(Mandatory = $false)]
    [string]$TempExtractPath = ".\GPOsTemp"
)

# Convert switches to booleans for internal use
$EnableDeleteProtection = -not $DisableDeleteProtection
$ImportGPOs = -not $SkipGPO

Import-Module ActiveDirectory
Import-Module GroupPolicy

#region Helper Functions
function Create-OUIfNotExists {
    param(
        [string]$Name,
        [string]$Path
    )
    
    try {
        $ouExists = Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel
        if (-not $ouExists) {
            New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $EnableDeleteProtection
            Write-Host "Created OU: $Name in $Path (Delete Protection: $EnableDeleteProtection)"
        }
        else {
            Set-ADOrganizationalUnit -Identity "OU=$Name,$Path" -ProtectedFromAccidentalDeletion $EnableDeleteProtection
            Write-Host "OU already exists: $Name in $Path (Updated Delete Protection: $EnableDeleteProtection)"
        }
    }
    catch {
        Write-Error ("Error creating/checking OU {0} in {1} - {2}" -f $Name, $Path, $_)
    }
}

function Create-AdminGroup {
    param(
        [string]$Name,
        [string]$Path
    )
    
    try {
        $groupExists = Get-ADGroup -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel
        if (-not $groupExists) {
            New-ADGroup -Name $Name -GroupScope Global -GroupCategory Security -Path $Path
            Write-Host "Created Group: $Name in $Path"
        }
        else {
            Write-Host "Group already exists: $Name in $Path"
        }
    }
    catch {
        Write-Error ("Error creating/checking Group {0} in {1} - {2}" -f $Name, $Path, $_)
    }
}

function Create-MigrationTable {
    param(
        [string]$Path,
        [string]$DomainNetBIOS
    )
    
    try {
        # Get domain information and well-known groups
        $domain = Get-ADDomain
        $domainDN = $domain.DistinguishedName
        $domainSID = $domain.DomainSid.Value
        $domainFQDN = $domain.DNSRoot
        
        # Create migration table XML content
        $migTableContent = @"
<?xml version="1.0" encoding="utf-8"?>
<MigrationTable xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.microsoft.com/GroupPolicy/GPOOperations/MigrationTable">
  <Mapping>
    <Source>customer.domain.fqdn</Source>
    <Destination>$domainFQDN</Destination>
  </Mapping>
  <Mapping>
    <Source>DOMAIN_NETBIOS</Source>
    <Destination>$DomainNetBIOS</Destination>
  </Mapping>
  <Mapping>
    <Source>Domain Users</Source>
    <Destination>$($(Get-ADGroup -Filter "SID -eq '$domainSID-513'").Name)</Destination>
  </Mapping>
"@

        # Add mappings for each tier admin group
        for ($i = 0; $i -lt $NumberOfTiers; $i++) {
            $groupName = "T${i}_Admins"
            $migTableContent += @"
  <Mapping>
    <Source>T${i}_Admins</Source>
    <Destination>$groupName</Destination>
  </Mapping>
"@
        }

        # Add TB_Admins mapping
        $migTableContent += @"
  <Mapping>
    <Source>TB_Admins</Source>
    <Destination>TB_Admins</Destination>
  </Mapping>
</MigrationTable>
"@

        # Save the migration table
        $migTablePath = Join-Path $Path "MigTable.migtable"
        $migTableContent | Out-File -FilePath $migTablePath -Encoding UTF8
        
        return $migTablePath
    }
    catch {
        Write-Error "Error creating migration table: $_"
    }
}
#endregion

try {
    #region Get Domain Info
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $domainName = $domain.DNSRoot
    Write-Host "Using domain: $domainName"
    #endregion

    #region Create OU Structure
    Write-Host "`nCreating OU Structure..."
    
    # Create Admin OU at root level
    Create-OUIfNotExists -Name "Admin" -Path $domainDN
    $adminPath = "OU=Admin,$domainDN"
    
    # Create Tier Base at root level
    Create-OUIfNotExists -Name "Tier Base" -Path $domainDN
    $basePath = "OU=Tier Base,$domainDN"
    
    Create-OUIfNotExists -Name "Users" -Path $basePath
    Create-OUIfNotExists -Name "Groups" -Path $basePath
    Create-OUIfNotExists -Name "Computers" -Path $basePath
    $computersPath = "OU=Computers,$basePath"
    Create-OUIfNotExists -Name "Windows" -Path $computersPath
    Create-OUIfNotExists -Name "Linux" -Path $computersPath
    
    # Create Base Tier under root Admin OU
    Create-OUIfNotExists -Name "Tier Base" -Path $adminPath
    $baseAdminPath = "OU=Tier Base,$adminPath"
    Create-OUIfNotExists -Name "Groups" -Path $baseAdminPath
    Create-OUIfNotExists -Name "Admins" -Path $baseAdminPath
    Create-AdminGroup -Name "TB_Admins" -Path "OU=Groups,$baseAdminPath"
    
    # Create other tiers under Admin OU
    for ($i = 0; $i -lt $NumberOfTiers; $i++) {
        $tierName = "Tier $i"
        Create-OUIfNotExists -Name $tierName -Path $adminPath
        $tierPath = "OU=$tierName,$adminPath"
        
        Create-OUIfNotExists -Name "Servers" -Path $tierPath
        Create-OUIfNotExists -Name "Groups" -Path $tierPath
        Create-OUIfNotExists -Name "Admins" -Path $tierPath
        
        # Create Windows and Linux OUs under Servers
        $serversPath = "OU=Servers,$tierPath"
        Create-OUIfNotExists -Name "Windows" -Path $serversPath
        Create-OUIfNotExists -Name "Linux" -Path $serversPath
        
        # Create tier admin group
        Create-AdminGroup -Name "T${i}_Admins" -Path "OU=Groups,$tierPath"
    }
    
    Write-Host "`nOU structure creation completed successfully!"
    #endregion

    #region Import and Configure GPOs
    if ($ImportGPOs) {
        Write-Host "`nStarting GPO import and configuration..."

        # Check if GPO zip exists
        if (-not (Test-Path $GpoZipPath)) {
            throw "GPO zip file not found at: $GpoZipPath"
        }

        # Extract GPO files
        Expand-Archive -Path $GpoZipPath -DestinationPath $TempExtractPath -Force

        # Copy ADMX/ADML files
        $sysvolPolicyPath = "\\$domainName\SYSVOL\$domainName\Policies"
        $policyDefinitionsPath = Join-Path $sysvolPolicyPath "PolicyDefinitions"
        $languagePath = Join-Path $policyDefinitionsPath "en-US"

        # Create PolicyDefinitions directories if they don't exist
        if (-not (Test-Path $policyDefinitionsPath)) {
            New-Item -Path $policyDefinitionsPath -ItemType Directory -Force
        }
        if (-not (Test-Path $languagePath)) {
            New-Item -Path $languagePath -ItemType Directory -Force
        }

        # Copy template files
        Copy-Item -Path (Join-Path $TempExtractPath "GPOs\Ubuntu-all.admx") -Destination $policyDefinitionsPath -Force
        Copy-Item -Path (Join-Path $TempExtractPath "GPOs\Ubuntu-all.adml") -Destination $languagePath -Force

        # Create migration table
        $migTablePath = Create-MigrationTable -Path $TempExtractPath -DomainNetBIOS $domain.NetBIOSName
        
        # Process each GPO directory
        Get-ChildItem -Path (Join-Path $TempExtractPath "GPOs") -Directory | ForEach-Object {
            $gpoDir = $_
            $gpoName = $gpoDir.Name
            
            if (-not ($gpoName -eq "PolicyDefinitions")) {
                Write-Host "`nProcessing GPO: $gpoName"

                # Import GPO
                try {
                    # Check if GPO already exists
                    $existingGPO = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
                    
                    if ($existingGPO) {
                        Write-Host "GPO '$gpoName' already exists. Removing existing links..."
                        # Remove existing links
                        $existingLinks = Get-ADOrganizationalUnit -Filter * | 
                        Where-Object { (Get-GPInheritance -Target $_).GpoLinks.DisplayName -contains $gpoName }
                        foreach ($link in $existingLinks) {
                            Remove-GPLink -Name $gpoName -Target $link.DistinguishedName -ErrorAction SilentlyContinue
                        }
                        
                        # Backup existing GPO before removal
                        $backupPath = Join-Path $env:TEMP "GPOBackup_$gpoName"
                        Backup-GPO -Name $gpoName -Path $backupPath
                        Remove-GPO -Name $gpoName -Force
                    }

                    # Import GPO with migration table
                    $backupId = (Get-ChildItem $gpoDir.FullName -Filter "Backup.xml" -Recurse).Directory.Name
                    $gpo = Import-GPO -BackupId $backupId `
                        -TargetName $gpoName `
                        -Path $gpoDir.FullName `
                        -CreateIfNeeded `
                        -MigrationTable $migTablePath

                    # Determine target OU based on GPO name
                    if ($gpoName -match '^Base') {
                        if ($gpoName -match 'Sudo') {
                            # Base Sudo Rights goes to Linux computers OU
                            $targetOU = "OU=Linux,OU=Computers,$basePath"
                        }
                        else {
                            # Base access control goes to Computers OU
                            $targetOU = "OU=Computers,$basePath"
                        }
                    }
                    elseif ($gpoName -match '^T(\d+)') {
                        $tierNum = [int]$Matches[1]
                        if ($tierNum -lt $NumberOfTiers) {
                            if ($gpoName -match 'Sudo') {
                                # Tier Sudo Rights goes to Linux servers OU
                                $targetOU = "OU=Linux,OU=Servers,OU=Tier $tierNum,$adminPath"
                            }
                            else {
                                # Tier access control goes to Servers OU
                                $targetOU = "OU=Servers,OU=Tier $tierNum,$adminPath"
                            }
                        }
                        else {
                            Write-Warning "Tier $tierNum GPO found but tier doesn't exist in OU structure - skipping"
                            continue
                        }
                    }
                    else {
                        Write-Warning "Unknown GPO format: $gpoName - skipping"
                        continue
                    }

                    # Link GPO
                    New-GPLink -Name $gpoName -Target $targetOU -ErrorAction Stop
                    Write-Host "Linked GPO '$gpoName' to OU: $targetOU"
                }
                catch {
                    Write-Error "Error processing GPO '$gpoName': $_"
                }
            }
        }
        Write-Host "`nGPO import and configuration completed successfully!"
    }
    else {
        Write-Host "`nSkipping GPO import (GPO import is enabled by default, use -SkipGPO to skip)"
    }
    #endregion

    Write-Host "`nComplete AD structure setup finished!"
    Write-Host "Delete Protection is set to: $(-not $DisableDeleteProtection)"
    if ($ImportGPOs) {
        Write-Host "GPOs were imported and configured"
    }
}
catch {
    Write-Error ("An error occurred during setup - {0}" -f $_)
}
finally {
    # Clean up
    if (Test-Path $TempExtractPath) {
        Remove-Item -Path $TempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}