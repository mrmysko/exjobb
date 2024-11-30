param(
    [Parameter(Mandatory = $true)]
    [int]$NumberOfTiers,
    
    [Parameter(Mandatory = $true)]
    [bool]$EnableDeleteProtection,
    
    [Parameter(Mandatory = $false)]
    [string]$GPOZipFile = "GPOs.zip"
)

Import-Module ActiveDirectory
Import-Module GroupPolicy

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
        return "OU=$Name,$Path"
    }
    catch {
        Write-Error ("Error creating/checking OU {0} in {1} - {2}" -f $Name, $Path, $_)
        return $null
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

function Copy-AdminTemplates {
    param(
        [string]$TempPath
    )
    
    try {
        # Get SYSVOL path from domain
        $domain = Get-ADDomain
        $sysvolPath = $domain.SysvolPath
        $policyDefsPath = Join-Path $sysvolPath "Policies\PolicyDefinitions"
        $languagePath = Join-Path $policyDefsPath "en-US"
        
        # Create directories if they don't exist
        if (-not (Test-Path $policyDefsPath)) {
            New-Item -ItemType Directory -Path $policyDefsPath -Force | Out-Null
        }
        if (-not (Test-Path $languagePath)) {
            New-Item -ItemType Directory -Path $languagePath -Force | Out-Null
        }
        
        # Look for and copy ADMX file
        $admxFile = Get-ChildItem -Path $TempPath -Filter "Ubuntu-all.admx" -Recurse | Select-Object -First 1
        if ($admxFile) {
            Copy-Item -Path $admxFile.FullName -Destination $policyDefsPath -Force
            Write-Host "Copied Ubuntu-all.admx to $policyDefsPath"
        }
        else {
            Write-Warning "Ubuntu-all.admx not found in the ZIP file"
        }
        
        # Look for and copy ADML file
        $admlFile = Get-ChildItem -Path $TempPath -Filter "Ubuntu-all.adml" -Recurse | Select-Object -First 1
        if ($admlFile) {
            Copy-Item -Path $admlFile.FullName -Destination $languagePath -Force
            Write-Host "Copied Ubuntu-all.adml to $languagePath"
        }
        else {
            Write-Warning "Ubuntu-all.adml not found in the ZIP file"
        }
    }
    catch {
        Write-Error ("Error copying admin templates - {0}" -f $_)
    }
}

function Import-AndLinkGPOs {
    param(
        [string]$ZipFile,
        [hashtable]$OUPaths
    )
    
    try {
        # Create a temporary directory for GPO extraction
        $tempPath = Join-Path $env:TEMP "GPOImport_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
        
        # Extract the ZIP file
        Expand-Archive -Path $ZipFile -DestinationPath $tempPath -Force
        
        # Copy ADMX/ADML files first
        Copy-AdminTemplates -TempPath $tempPath
        
        # Process each GPO directory
        Get-ChildItem -Path $tempPath -Directory | ForEach-Object {
            $gpoName = $_.Name
            $gpoPath = $_.FullName
            
            Write-Host "Processing GPO: $gpoName"
            
            # Import GPO
            $gpo = Import-GPO -BackupGpoName $gpoName -TargetName $gpoName -Path $gpoPath -CreateIfNeeded
            
            # Determine target OU based on GPO name
            $targetOU = $null
            
            switch -Regex ($gpoName) {
                # Tier-specific Linux GPOs
                '^T(\d+)\sSudo\sRights$' {
                    $tierNum = $matches[1]
                    $targetOU = $OUPaths["Tier${tierNum}LinuxServers"]
                }
                
                # Tier-specific Server GPOs
                '^T(\d+)\sServers\s' {
                    $tierNum = $matches[1]
                    $targetOU = $OUPaths["Tier${tierNum}Servers"]
                }
                
                # Base Tier Linux GPOs
                '^Base\sSudo\sRights$' {
                    $targetOU = $OUPaths["BaseLinux"]
                }
                
                # Add more patterns as needed
            }
            
            # Link GPO if target OU was found
            if ($targetOU) {
                Write-Host "Linking GPO '$gpoName' to OU: $targetOU"
                New-GPLink -Name $gpoName -Target $targetOU -ErrorAction SilentlyContinue
            }
            else {
                Write-Warning "No matching OU found for GPO: $gpoName"
            }
        }
    }
    catch {
        Write-Error ("Error processing GPOs - {0}" -f $_)
    }
    finally {
        # Cleanup
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force
        }
    }
}

try {
    # Get the domain information
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $rootDomain = $domain.DNSRoot
    Write-Host "Using domain: $rootDomain"
    
    # Store OU paths for GPO linking
    $ouPaths = @{}
    
    # Create Admin OU at root level
    Create-OUIfNotExists -Name "Admin" -Path $domainDN
    $adminPath = "OU=Admin,$domainDN"
    
    # Create Tier Base at root level
    Create-OUIfNotExists -Name "Tier Base" -Path $domainDN
    $basePath = "OU=Tier Base,$domainDN"
    
    Create-OUIfNotExists -Name "Users" -Path $basePath
    Create-OUIfNotExists -Name "Groups" -Path $basePath
    $computersOU = Create-OUIfNotExists -Name "Computers" -Path $basePath
    $computersPath = "OU=Computers,$basePath"
    Create-OUIfNotExists -Name "Windows" -Path $computersPath
    $baseLinuxOU = Create-OUIfNotExists -Name "Linux" -Path $computersPath
    $ouPaths["BaseLinux"] = $baseLinuxOU
    
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
        
        $serversOU = Create-OUIfNotExists -Name "Servers" -Path $tierPath
        Create-OUIfNotExists -Name "Groups" -Path $tierPath
        Create-OUIfNotExists -Name "Admins" -Path $tierPath
        
        # Store the Servers OU path for GPO linking
        $ouPaths["Tier${i}Servers"] = $serversOU
        
        # Create Windows and Linux OUs under Servers
        $serversPath = "OU=Servers,$tierPath"
        Create-OUIfNotExists -Name "Windows" -Path $serversPath
        $linuxOU = Create-OUIfNotExists -Name "Linux" -Path $serversPath
        $ouPaths["Tier${i}LinuxServers"] = $linuxOU
        
        # Create tier admin group
        Create-AdminGroup -Name "T${i}_Admins" -Path "OU=Groups,$tierPath"
    }
    
    # Import and link GPOs if the zip file exists
    if (Test-Path $GPOZipFile) {
        Write-Host "`nImporting and linking GPOs from $GPOZipFile..."
        Import-AndLinkGPOs -ZipFile $GPOZipFile -OUPaths $ouPaths
    }
    else {
        Write-Warning "GPO zip file not found: $GPOZipFile"
    }
    
    Write-Host "`nOU structure creation completed successfully!"
    Write-Host "Delete Protection is set to: $EnableDeleteProtection"
}
catch {
    Write-Error ("An error occurred during OU structure creation - {0}" -f $_)
}