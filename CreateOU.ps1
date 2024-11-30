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
        [ValidateNotNullOrEmpty()]
        [string]$TempPath
    )
    
    try {
        # Get SYSVOL path
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
        
        # Set source paths (in GPOs directory)
        $gposPath = Join-Path $TempPath "GPOs"
        $admxSource = Join-Path $gposPath "Ubuntu-all.admx"
        $admlSource = Join-Path $gposPath "Ubuntu-all.adml"
        
        # Copy ADMX file
        if (Test-Path $admxSource) {
            Copy-Item -Path $admxSource -Destination $policyDefsPath -Force
            Write-Host "Copied Ubuntu-all.admx to $policyDefsPath"
        }
        else {
            Write-Error "Ubuntu-all.admx not found in $gposPath"
        }
        
        # Copy ADML file
        if (Test-Path $admlSource) {
            Copy-Item -Path $admlSource -Destination $languagePath -Force
            Write-Host "Copied Ubuntu-all.adml to $languagePath"
        }
        else {
            Write-Error "Ubuntu-all.adml not found in $gposPath"
        }
    }
    catch {
        Write-Error ("Error copying admin templates - {0}" -f $_)
        throw
    }
}

function Import-AndLinkGPOs {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ZipFile,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable]$OUPaths
    )
    
    $tempPath = Join-Path $env:TEMP "GPOImport_$(Get-Random)"
    
    try {
        # Create temporary directory and extract ZIP
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
        Write-Host "Created temporary directory: $tempPath"
        
        Expand-Archive -Path $ZipFile -DestinationPath $tempPath -Force
        Write-Host "Extracted $ZipFile to $tempPath"
        
        # Copy admin templates first
        Copy-AdminTemplates -TempPath $tempPath
        
        # Process GPOs
        $gpoDirectories = Get-ChildItem -Path $tempPath -Directory | 
        Where-Object { Test-Path (Join-Path $_.FullName "Backup.xml") }
        
        foreach ($gpoDir in $gpoDirectories) {
            $gpoName = $gpoDir.Name
            $gpoPath = $gpoDir.FullName
            
            Write-Host "Processing GPO: $gpoName from $gpoPath"
            
            try {
                $gpo = Import-GPO -BackupGpoName $gpoName -TargetName $gpoName -Path $gpoPath -CreateIfNeeded
                Write-Host "Successfully imported GPO: $gpoName"
                
                # Determine target OU based on GPO name
                $targetOU = $null
                
                switch -Regex ($gpoName) {
                    '^T(\d+)\sSudo\sRights$' {
                        $tierNum = $matches[1]
                        $targetOU = $OUPaths["Tier${tierNum}LinuxServers"]
                        Write-Host "Matched Tier $tierNum Linux GPO pattern"
                    }
                    '^T(\d+)\sServers\s' {
                        $tierNum = $matches[1]
                        $targetOU = $OUPaths["Tier${tierNum}Servers"]
                        Write-Host "Matched Tier $tierNum Servers GPO pattern"
                    }
                    '^Base\sSudo\sRights$' {
                        $targetOU = $OUPaths["BaseLinux"]
                        Write-Host "Matched Base Linux GPO pattern"
                    }
                }
                
                if ($targetOU) {
                    Write-Host "Linking GPO '$gpoName' to OU: $targetOU"
                    New-GPLink -Name $gpoName -Target $targetOU -ErrorAction Stop
                    Write-Host "Successfully linked GPO '$gpoName' to OU: $targetOU"
                }
                else {
                    Write-Warning "No matching OU found for GPO: $gpoName"
                }
            }
            catch {
                Write-Error "Error processing GPO $gpoName - $_"
            }
        }
    }
    catch {
        Write-Error "Error in Import-AndLinkGPOs: $_"
        throw
    }
    finally {
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
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
    $gpoZipPath = Resolve-Path $GPOZipFile -ErrorAction Stop
    if (Test-Path $gpoZipPath) {
        Write-Host "`nImporting and linking GPOs from $gpoZipPath..."
        Import-AndLinkGPOs -ZipFile $gpoZipPath -OUPaths $ouPaths
    }
    else {
        Write-Warning "GPO zip file not found: $gpoZipPath"
    }
    
    Write-Host "`nOU structure creation completed successfully!"
    Write-Host "Delete Protection is set to: $EnableDeleteProtection"
}
catch {
    Write-Error ("An error occurred during OU structure creation - {0}" -f $_)
}