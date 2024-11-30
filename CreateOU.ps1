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
        [Parameter(Mandatory = $true)]
        [string]$TempPath
    )
    
    try {
        # Validate temp path
        if (-not (Test-Path $TempPath)) {
            Write-Error "Temporary path does not exist: $TempPath"
            return
        }

        # Get SYSVOL path from domain
        $domain = Get-ADDomain
        $sysvolPath = $domain.SysvolPath
        $policyDefsPath = Join-Path $sysvolPath "Policies\PolicyDefinitions"
        $languagePath = Join-Path $policyDefsPath "en-US"
        
        Write-Host "PolicyDefinitions path: $policyDefsPath"
        Write-Host "Language path: $languagePath"
        
        # Create directories if they don't exist
        if (-not (Test-Path $policyDefsPath)) {
            New-Item -ItemType Directory -Path $policyDefsPath -Force | Out-Null
            Write-Host "Created PolicyDefinitions directory: $policyDefsPath"
        }
        if (-not (Test-Path $languagePath)) {
            New-Item -ItemType Directory -Path $languagePath -Force | Out-Null
            Write-Host "Created language directory: $languagePath"
        }
        
        # Search for ADMX file with more detailed error handling
        Write-Host "Searching for ADMX file in $TempPath"
        $admxFile = Get-ChildItem -Path $TempPath -Filter "Ubuntu-all.admx" -Recurse -ErrorAction Stop | Select-Object -First 1
        if ($admxFile) {
            Write-Host "Found ADMX file: $($admxFile.FullName)"
            Copy-Item -Path $admxFile.FullName -Destination $policyDefsPath -Force
            Write-Host "Copied Ubuntu-all.admx to $policyDefsPath"
        }
        else {
            Write-Warning "Ubuntu-all.admx not found in path: $TempPath"
        }
        
        # Search for ADML file with more detailed error handling
        Write-Host "Searching for ADML file in $TempPath"
        $admlFile = Get-ChildItem -Path $TempPath -Filter "Ubuntu-all.adml" -Recurse -ErrorAction Stop | Select-Object -First 1
        if ($admlFile) {
            Write-Host "Found ADML file: $($admlFile.FullName)"
            Copy-Item -Path $admlFile.FullName -Destination $languagePath -Force
            Write-Host "Copied Ubuntu-all.adml to $languagePath"
        }
        else {
            Write-Warning "Ubuntu-all.adml not found in path: $TempPath"
        }
        
        # Verify files were copied successfully
        if ((Test-Path (Join-Path $policyDefsPath "Ubuntu-all.admx")) -and 
            (Test-Path (Join-Path $languagePath "Ubuntu-all.adml"))) {
            Write-Host "Successfully copied both ADMX and ADML files"
        }
        else {
            Write-Warning "One or both template files may not have been copied successfully"
        }
    }
    catch {
        Write-Error ("Error copying admin templates - {0}" -f $_)
        throw  # Re-throw the error to be handled by the calling function
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
        Write-Host "Created temporary directory: $tempPath"
        
        # Extract the ZIP file
        Write-Host "Extracting $ZipFile to $tempPath"
        Expand-Archive -Path $ZipFile -DestinationPath $tempPath -Force
        
        # Copy ADMX/ADML files first with explicit path
        Write-Host "Copying administrative templates..."
        Copy-AdminTemplates -TempPath $tempPath
        
        # Process each GPO directory
        Get-ChildItem -Path $tempPath -Directory | ForEach-Object {
            $gpoName = $_.Name
            $gpoPath = $_.FullName
            
            # Skip if it's not a GPO directory (e.g., if it's an admin template directory)
            if (-not (Test-Path (Join-Path $gpoPath "Backup.xml"))) {
                Write-Host "Skipping non-GPO directory: $gpoName"
                return
            }
            
            Write-Host "Processing GPO: $gpoName"
            
            # Import GPO
            try {
                $gpo = Import-GPO -BackupGpoName $gpoName -TargetName $gpoName -Path $gpoPath -CreateIfNeeded
                Write-Host "Successfully imported GPO: $gpoName"
            }
            catch {
                Write-Error "Failed to import GPO $gpoName - $_"
                return
            }
            
            # Determine target OU based on GPO name
            $targetOU = $null
            
            switch -Regex ($gpoName) {
                # Tier-specific Linux GPOs
                '^T(\d+)\sSudo\sRights$' {
                    $tierNum = $matches[1]
                    $targetOU = $OUPaths["Tier${tierNum}LinuxServers"]
                    Write-Host "Matched Tier $tierNum Linux GPO pattern"
                }
                
                # Tier-specific Server GPOs
                '^T(\d+)\sServers\s' {
                    $tierNum = $matches[1]
                    $targetOU = $OUPaths["Tier${tierNum}Servers"]
                    Write-Host "Matched Tier $tierNum Servers GPO pattern"
                }
                
                # Base Tier Linux GPOs
                '^Base\sSudo\sRights$' {
                    $targetOU = $OUPaths["BaseLinux"]
                    Write-Host "Matched Base Linux GPO pattern"
                }
            }
            
            # Link GPO if target OU was found
            if ($targetOU) {
                Write-Host "Linking GPO '$gpoName' to OU: $targetOU"
                try {
                    New-GPLink -Name $gpoName -Target $targetOU -ErrorAction Stop
                    Write-Host "Successfully linked GPO '$gpoName' to OU: $targetOU"
                }
                catch {
                    Write-Error "Failed to link GPO $gpoName to $targetOU - $_"
                }
            }
            else {
                Write-Warning "No matching OU found for GPO: $gpoName"
            }
        }
    }
    catch {
        Write-Error ("Error processing GPOs - {0}" -f $_)
        throw
    }
    finally {
        # Cleanup
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force
            Write-Host "Cleaned up temporary directory: $tempPath"
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