param(
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = ".\\GPOBackup",
    
    [Parameter(Mandatory = $false)]
    [string]$MigTablePath = ".\\gpo-migration.migtable",
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# Convert to absolute paths using current directory
$BackupPath = Join-Path $PWD.Path "GPOBackup"
$MigTablePath = Join-Path $PWD.Path "gpo-migration.migtable"

Write-Host "Starting GPO import process..."
Write-Host "Using backup path: $BackupPath"
Write-Host "Using migration table: $MigTablePath"

# Verify paths exist
if (-not (Test-Path $BackupPath)) {
    throw "Backup path not found: $BackupPath"
}

if (-not (Test-Path $MigTablePath)) {
    throw "Migration table not found: $MigTablePath"
}

# Function to read GPO name from the XML file in the backup folder
function Get-GPONameFromBackup {
    param($BackupFolderPath)
    
    $backupXmlPath = Join-Path $BackupFolderPath "Backup.xml"
    if (Test-Path $backupXmlPath) {
        try {
            [xml]$backupInfo = Get-Content $backupXmlPath -ErrorAction Stop
            return $backupInfo.GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.DisplayName.InnerText
        }
        catch {
            Write-Warning "Error reading backup XML in $BackupFolderPath: $_"
            return $null
        }
    }
    else {
        Write-Warning "Backup XML file not found in $BackupFolderPath"
    }
    return $null
}

# Process all backup folders
$backupFolders = Get-ChildItem -Path $BackupPath -Directory

foreach ($folder in $backupFolders) {
    try {
        $backupId = $folder.Name
        $gpoName = Get-GPONameFromBackup -BackupFolderPath $folder.FullName

        if (-not $gpoName) {
            Write-Warning "Could not determine GPO name for backup ID: $backupId"
            continue
        }

        Write-Host "Processing GPO: $gpoName (Backup ID: $backupId)"

        # Construct the Import-GPO command with the extracted GPO name
        $cmd = "Import-GPO -BackupId $backupId -Path $BackupPath -MigrationTable $MigTablePath -TargetName $gpoName"
        Write-Host "Executing: $cmd"

        if (-not $WhatIf) {
            Import-GPO -BackupId $backupId -Path $BackupPath -MigrationTable $MigTablePath -TargetName $gpoName
            Write-Host "Successfully imported: $gpoName" -ForegroundColor Green
        }
        else {
            Write-Host "WhatIf: Would import $gpoName (TargetName: $gpoName)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Failed to import GPO (Backup ID: $backupId). Error: $_"
    }
}
