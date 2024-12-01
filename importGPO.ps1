# Import and link GPOs to appropriate OUs
param(
    [Parameter(Mandatory = $false)]
    [string]$ZipPath = ".\GPOs.zip",
    
    [Parameter(Mandatory = $false)]
    [string]$TempExtractPath = ".\GPOsTemp"
)

try {
    # Import required modules
    Import-Module ActiveDirectory
    Import-Module GroupPolicy

    # Get domain information
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $domainName = $domain.DNSRoot

    # First, extract the GPO templates
    Write-Host "Extracting GPO files from $ZipPath"
    Expand-Archive -Path $ZipPath -DestinationPath $TempExtractPath -Force

    # Copy ADMX/ADML files
    $sysvolPolicyPath = "\\$domainName\SYSVOL\$domainName\Policies"
    $policyDefinitionsPath = Join-Path $sysvolPolicyPath "PolicyDefinitions"
    $languagePath = Join-Path $policyDefinitionsPath "en-US"

    # Create directories if they don't exist
    if (-not (Test-Path $policyDefinitionsPath)) {
        New-Item -Path $policyDefinitionsPath -ItemType Directory -Force
    }
    if (-not (Test-Path $languagePath)) {
        New-Item -Path $languagePath -ItemType Directory -Force
    }

    # Copy template files
    Copy-Item -Path (Join-Path $TempExtractPath "GPOs\Ubuntu-all.admx") -Destination $policyDefinitionsPath -Force
    Copy-Item -Path (Join-Path $TempExtractPath "GPOs\Ubuntu-all.adml") -Destination $languagePath -Force

    # Get existing tier OUs
    $tierOUs = Get-ADOrganizationalUnit -Filter "Name -like 'Tier *'" -SearchBase "OU=Admin,$domainDN" |
    Where-Object { $_.Name -match 'Tier \d+' } |
    ForEach-Object { 
        if ($_.Name -match 'Tier (\d+)') { 
            [int]$Matches[1]
        }
    } |
    Sort-Object

    Write-Host "Found tiers: $($tierOUs -join ', ')"

    # Initialize GPO mapping with base policies
    $gpoMapping = @{
        "Base Sudo Rights"              = @{
            OU      = "OU=Linux,OU=Computers,OU=Tier Base,$domainDN"
            Enabled = $true
            Order   = 1
        }
        "Base Computers Access Control" = @{
            OU      = "OU=Tier Base,$domainDN"
            Enabled = $true
            Order   = 1
        }
    }

    # Add tier-specific policies to mapping
    foreach ($tier in $tierOUs) {
        $gpoMapping["T$tier Servers Access Control"] = @{
            OU      = "OU=Servers,OU=Tier $tier,OU=Admin,$domainDN"
            Enabled = $true
            Order   = 1
        }
        $gpoMapping["T$tier Sudo Rights"] = @{
            OU      = "OU=Linux,OU=Servers,OU=Tier $tier,OU=Admin,$domainDN"
            Enabled = $true
            Order   = 1
        }
    }

    # Process each GPO directory
    Get-ChildItem -Path (Join-Path $TempExtractPath "GPOs") -Directory | ForEach-Object {
        $gpoDir = $_
        $gpoName = $gpoDir.Name
        Write-Host "`nProcessing GPO: $gpoName"

        # Check if this is a known GPO
        if (-not $gpoMapping.ContainsKey($gpoName)) {
            Write-Warning "GPO '$gpoName' not mapped to any OU - checking if it's a tier-specific GPO..."
            
            # Check if it matches the pattern for tier-specific GPOs
            if ($gpoName -match '^T(\d+) (Servers Access Control|Sudo Rights)$') {
                $tierNum = [int]$Matches[1]
                $gpoType = $Matches[2]
                
                if ($tierOUs -contains $tierNum) {
                    # Add to mapping dynamically
                    $targetOU = if ($gpoType -eq "Sudo Rights") {
                        "OU=Linux,OU=Servers,OU=Tier $tierNum,OU=Admin,$domainDN"
                    }
                    else {
                        "OU=Servers,OU=Tier $tierNum,OU=Admin,$domainDN"
                    }
                    
                    $gpoMapping[$gpoName] = @{
                        OU      = $targetOU
                        Enabled = $true
                        Order   = 1
                    }
                    Write-Host "Dynamically added mapping for tier $tierNum GPO: $gpoName"
                }
                else {
                    Write-Warning "Tier $tierNum doesn't exist in AD - skipping GPO: $gpoName"
                    continue
                }
            }
            else {
                Write-Warning "Unknown GPO format - skipping"
                continue
            }
        }

        $targetOU = $gpoMapping[$gpoName].OU

        # Verify OU exists
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$targetOU'" -ErrorAction SilentlyContinue)) {
            Write-Warning "Target OU does not exist: $targetOU"
            continue
        }

        # Import GPO
        try {
            # Check if GPO already exists
            $existingGPO = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
            
            if ($existingGPO) {
                Write-Host "GPO '$gpoName' already exists. Removing existing links..."
                # Remove existing links before updating
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
            Write-Host "Importing GPO from $($gpoDir.FullName)"
            Import-GPO -BackupId (Get-ChildItem $gpoDir.FullName -Filter "Backup.xml" -Recurse).Directory.Name `
                -TargetName $gpoName `
                -Path $gpoDir.FullName `
                -CreateIfNeeded

            # Create GPO link
            Write-Host "Linking GPO '$gpoName' to OU: $targetOU"
            $gpoLink = New-GPLink -Name $gpoName -Target $targetOU -ErrorAction Stop
            
            # Set link enabled state
            if ($null -ne $gpoLink) {
                $gpoLink.Enabled = $gpoMapping[$gpoName].Enabled
            }
            
            Write-Host "Successfully processed GPO: $gpoName"
        }
        catch {
            Write-Error "Error processing GPO '$gpoName': $_"
        }
    }

    Write-Host "`nGPO import and linking completed!"
}
catch {
    Write-Error "An error occurred during GPO processing: $_"
}
finally {
    # Clean up
    if (Test-Path $TempExtractPath) {
        Remove-Item -Path $TempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}