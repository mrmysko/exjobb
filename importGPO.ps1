# Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [string]$ZipFilePath,
    
    [Parameter(Mandatory = $true)]
    [string]$DomainName
)

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
    $gpoBackups = Get-ChildItem -Path $tempDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "Backup.xml")
    }
    
    if ($gpoBackups) {
        Write-Host "Found GPO backups to import:" -ForegroundColor Cyan
        foreach ($gpoBackup in $gpoBackups) {
            $backupXml = [xml](Get-Content (Join-Path $gpoBackup.FullName "Backup.xml"))
            $gpoName = $backupXml.BackupInst.GPODisplayName
            Write-Host "Importing GPO: $gpoName" -ForegroundColor Cyan
            
            try {
                Import-GPO -BackupGpoName $gpoName -TargetName $gpoName -Path $gpoBackup.FullName -CreateIfNeeded
                Write-Host "Successfully imported GPO: $gpoName" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to import GPO: $gpoName`nError: $_"
            }
        }
    }
    else {
        Write-Warning "No GPO backups found in the ZIP file"
    }
    
    # Cleanup
    Write-Host "Cleaning up temporary files..." -ForegroundColor Cyan
    Remove-Item $tempDir -Recurse -Force
}

try {
    # Verify the zip file exists
    if (-not (Test-Path $ZipFilePath)) {
        throw "ZIP file not found: $ZipFilePath"
    }
    
    # Import required module
    if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
        throw "GroupPolicy PowerShell module not found. Please ensure you're running this on a domain controller or system with RSAT tools installed."
    }
    Import-Module GroupPolicy
    
    # Execute deployment
    Deploy-GPOFiles -ZipPath $ZipFilePath -Domain $DomainName
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Deployment failed: $_"
    exit 1
}