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

function Update-GpoSecuritySettings {
    param(
        [string]$GpoName,
        [string[]]$DenyLogonGroups
    )
    
    try {
        Write-Host "Updating security settings for GPO: $GpoName"
        
        # Get the GPO's ID GUID
        $gpo = Get-GPO -Name $GpoName
        $gpoId = $gpo.Id.Guid
        $gpoPath = "\\$domainName\SYSVOL\$domainName\Policies\{$gpoId}\Machine\Microsoft\Windows NT\SecEdit"
        
        # Create the SecEdit working directory if it doesn't exist
        if (-not (Test-Path $gpoPath)) {
            New-Item -Path $gpoPath -ItemType Directory -Force | Out-Null
        }
        
        # Get both Domain Name and SIDs for all groups
        $sidEntries = @()
        foreach ($group in $DenyLogonGroups) {
            $adGroup = Get-ADGroup -Identity $group -ErrorAction Stop
            # Format: "*DOMAIN\GroupName,SID"
            $sidEntries += "*$domainName\$group,$($adGroup.SID.Value)"
        }
        $sidList = $sidEntries -join ','
        
        # Create the security template content
        $infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeDenyBatchLogonRight = $sidList
SeDenyServiceLogonRight = $sidList
SeDenyInteractiveLogonRight = $sidList
SeDenyRemoteInteractiveLogonRight = $sidList
"@
        
        # Save the template
        $infFile = Join-Path $gpoPath "gpttmpl.inf"
        $infContent | Out-File -FilePath $infFile -Encoding unicode -Force
        
        Write-Host "Completed security settings update for GPO: $GpoName"
    }
    catch {
        Write-Error "Error updating security settings for GPO $GpoName : $_"
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

        # Get all domain users for base policy
        $allUsersGroup = "Domain Users"
        
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

                    # Import GPO
                    $gpo = Import-GPO -BackupId (Get-ChildItem $gpoDir.FullName -Filter "Backup.xml" -Recurse).Directory.Name `
                        -TargetName $gpoName `
                        -Path $gpoDir.FullName `
                        -CreateIfNeeded

                    # Determine target OU and security settings based on GPO name
                    if ($gpoName -match '^Base') {
                        # For base computers
                        $targetOU = $basePath
                        $denyGroups = @()
                        for ($i = 0; $i -lt $NumberOfTiers; $i++) {
                            $denyGroups += "T${i}_Admins"
                        }
                    }
                    elseif ($gpoName -match '^T(\d+)') {
                        $tierNum = [int]$Matches[1]
                        if ($tierNum -lt $NumberOfTiers) {
                            $targetOU = "OU=Servers,OU=Tier $tierNum,$adminPath"
                            # Deny everyone except this tier's admins
                            $denyGroups = @($allUsersGroup)
                            for ($i = 0; $i -lt $NumberOfTiers; $i++) {
                                if ($i -ne $tierNum) {
                                    $denyGroups += "T${i}_Admins"
                                }
                            }
                            $denyGroups += "TB_Admins"
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

                    # Update security settings
                    Update-GpoSecuritySettings -GpoName $gpoName -DenyLogonGroups $denyGroups
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