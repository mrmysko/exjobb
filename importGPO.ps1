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
    $gpoBackups = Get-ChildItem -Path $tempDir -Directory | Where-Object {
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
            $backupXmlPath = Join-Path $gpoBackup.FullName "Backup.xml"
            Write-Host "`nProcessing backup XML: $backupXmlPath" -ForegroundColor Yellow
            
            try {
                # Load and validate the backup XML
                $backupXml = [xml](Get-Content $backupXmlPath -ErrorAction Stop)
                Write-Host "Successfully loaded XML file" -ForegroundColor Green
                
                if ($null -eq $backupXml.BackupInst) {
                    Write-Warning "Invalid XML structure - missing BackupInst node"
                    Write-Host "XML Content:" -ForegroundColor Yellow
                    Get-Content $backupXmlPath | Write-Host
                    continue
                }

                if ($null -eq $backupXml.BackupInst.GPODisplayName) {
                    Write-Warning "GPO Display Name is null in $($gpoBackup.Name)"
                    Write-Host "XML Content:" -ForegroundColor Yellow
                    Get-Content $backupXmlPath | Write-Host
                    continue
                }
                
                $gpoName = $backupXml.BackupInst.GPODisplayName.Trim()
                if ([string]::IsNullOrWhiteSpace($gpoName)) {
                    Write-Warning "GPO Name is empty in $($gpoBackup.Name)"
                    continue
                }
                
                Write-Host "Importing GPO: $gpoName (From directory: $($gpoBackup.Name))" -ForegroundColor Cyan
                
                # Get backup ID from XML
                $backupId = $backupXml.BackupInst.ID
                if ([string]::IsNullOrWhiteSpace($backupId)) {
                    Write-Warning "Backup ID is missing in $($gpoBackup.Name)"
                    continue
                }

                # Attempt the import with full path information
                Import-GPO -BackupId $backupId -TargetName $gpoName -Path $gpoBackup.Parent.FullName -CreateIfNeeded
                Write-Host "Successfully imported GPO: $gpoName" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed processing GPO backup in directory $($gpoBackup.Name)"
                Write-Warning "Error: $_"
                Write-Host "Full backup path: $($gpoBackup.FullName)" -ForegroundColor Yellow
                
                # Try to display XML content for debugging
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