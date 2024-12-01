# Requires -RunAsAdministrator

function Deploy-GPOFiles {
    param (
        [string]$ZipPath,
        [string]$Domain
    )
    
    # Create temporary directory for extraction
    $tempDir = Join-Path $env:TEMP "GPODeployment"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    # Extract the zip file
    Write-Host "Extracting ZIP file..." -ForegroundColor Cyan
    Expand-Archive -Path $ZipPath -DestinationPath $tempDir -Force
    
    # Define SYSVOL paths
    $policyDefPath = "\\$Domain\SYSVOL\$Domain\Policies\PolicyDefinitions"
    $languagePath = Join-Path $policyDefPath "en-US"
    
    # Create directories if they don't exist
    if (-not (Test-Path $policyDefPath)) {
        New-Item -ItemType Directory -Path $policyDefPath -Force | Out-Null
    }
    if (-not (Test-Path $languagePath)) {
        New-Item -ItemType Directory -Path $languagePath -Force | Out-Null
    }
    
    # Copy ADMX file
    $admxFile = Get-ChildItem -Path $tempDir -Filter "Ubuntu-all.admx" -Recurse
    if ($admxFile) {
        Write-Host "Copying ADMX file to $policyDefPath" -ForegroundColor Cyan
        Copy-Item -Path $admxFile.FullName -Destination $policyDefPath -Force
    }
    else {
        Write-Warning "Ubuntu-all.admx not found in the ZIP file"
    }
    
    # Copy ADML file
    $admlFile = Get-ChildItem -Path $tempDir -Filter "Ubuntu-all.adml" -Recurse
    if ($admlFile) {
        Write-Host "Copying ADML file to $languagePath" -ForegroundColor Cyan
        Copy-Item -Path $admlFile.FullName -Destination $languagePath -Force
    }
    else {
        Write-Warning "Ubuntu-all.adml not found in the ZIP file"
    }
    
    # Import GPOs
    Write-Host "`nSearching for GPO backups..." -ForegroundColor Cyan
    $gpoBackups = Get-ChildItem -Path $tempDir -Directory -Recurse | Where-Object {
        $xmlPath = Join-Path $_.FullName "Backup.xml"
        $hasBackupXml = Test-Path $xmlPath
        if ($hasBackupXml) {
            Write-Host "Found backup in directory: $($_.FullName)" -ForegroundColor Yellow
        }
        $hasBackupXml
    }
    
    if ($gpoBackups) {
        Write-Host "`nFound GPO backups to import:" -ForegroundColor Cyan
        foreach ($gpoBackup in $gpoBackups) {
            try {
                # Get the backup directory name (GUID)
                $backupId = $gpoBackup.Name
                
                # Try to get GPO name from DomainSysvol\GPO\gpreport.xml
                $gpreportPath = Join-Path $gpoBackup.FullName "DomainSysvol\GPO\gpreport.xml"
                if (Test-Path $gpreportPath) {
                    [xml]$gpreport = Get-Content $gpreportPath
                    $gpoName = $gpreport.GPO.Name
                }
                
                # If gpreport.xml not found or name not in it, try backup.xml
                if (-not $gpoName) {
                    $backupXmlPath = Join-Path $gpoBackup.FullName "backup.xml"
                    if (Test-Path $backupXmlPath) {
                        [xml]$backupXml = Get-Content $backupXmlPath
                        # Try to get from SecurityDescriptor first
                        $gpoName = $backupXml.GroupPolicyBackupScheme.GroupPolicyObject.SecurityDescriptor.DSPath.Split(',')[0] -replace 'CN=', ''
                        # If not found, try GroupPolicyObject name
                        if (-not $gpoName) {
                            $gpoName = $backupXml.GroupPolicyBackupScheme.GroupPolicyObject.Name
                        }
                    }
                }
                
                # If still no name found, use backup ID
                if (-not $gpoName) {
                    $gpoName = $backupId
                }

                Write-Host "`nProcessing GPO: $gpoName (Backup ID: $backupId)" -ForegroundColor Yellow
                
                # Import the GPO
                Import-GPO -BackupId $backupId -Path $gpoBackup.Parent.FullName -TargetName $gpoName -CreateIfNeeded
                Write-Host "Successfully imported GPO: $gpoName" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed processing GPO backup in directory $($gpoBackup.Name)"
                Write-Warning "Error: $_"
                Write-Host "Full backup path: $($gpoBackup.FullName)" -ForegroundColor Yellow
                
                # Try to display backup.xml content for debugging
                $backupXmlPath = Join-Path $gpoBackup.FullName "backup.xml"
                if (Test-Path $backupXmlPath) {
                    Write-Host "Backup.xml content:" -ForegroundColor Yellow
                    Get-Content $backupXmlPath | Write-Host
                }
            }
        }
    }
    else {
        Write-Warning "No GPO backups found in the ZIP file at path: $tempDir"
        Write-Host "`nDirectory contents:" -ForegroundColor Yellow
        Get-ChildItem $tempDir -Recurse | Select-Object FullName | Format-Table -AutoSize
    }
    
    # Cleanup
    Write-Host "`nCleaning up temporary files..." -ForegroundColor Cyan
    Remove-Item $tempDir -Recurse -Force
}

try {
    # Set path to GPOs.zip in current directory
    $zipPath = Join-Path $PWD.Path "GPOs.zip"
    
    # Verify the zip file exists
    if (-not (Test-Path $zipPath)) {
        throw "GPOs.zip not found in current directory: $zipPath"
    }
    
    # Get current domain
    $domain = (Get-ADDomain).DNSRoot
    Write-Host "Using domain: $domain" -ForegroundColor Cyan
    
    # Import required module
    if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
        throw "GroupPolicy PowerShell module not found. Please ensure you're running this on a domain controller or system with RSAT tools installed."
    }
    Import-Module GroupPolicy
    
    # Execute deployment
    Deploy-GPOFiles -ZipPath $zipPath -Domain $domain
    Write-Host "`nDeployment completed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Deployment failed: $_"
    exit 1
}