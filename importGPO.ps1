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

# Function to translate source SIDs to destination SIDs
function Translate-SID {
    param($sourceSID, $sourceName)
    try {
        $destinationGroup = Get-ADGroup -Filter { Name -eq $sourceName }
        return $destinationGroup.SID
    }
    catch {
        Write-Warning "Could not find a matching group for $sourceName ($sourceSID) in the destination domain."
        return $null
    }
}

# Read migration table and map SIDs
$migrationTableXml = [xml](Get-Content $MigTablePath)
$mappings = @{}

foreach ($mapping in $migrationTableXml.MigrationTable.Mapping) {
    $sourceSID = $mapping.Source
    $destinationName = $mapping.Destination
    $destinationSID = Translate-SID -sourceSID $sourceSID -sourceName $destinationName
    if ($destinationSID) {
        $mappings[$sourceSID] = $destinationSID
    }
    else {
        Write-Warning "No destination SID found for source SID: $sourceSID"
    }
}

# Process GPO backups
$backupFolders = Get-ChildItem -Path $BackupPath -Directory

foreach ($folder in $backupFolders) {
    try {
        $backupId = $folder.Name
        $gpoName = (Get-Content (Join-Path $folder.FullName "Backup.xml")).GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.DisplayName

        Write-Host "Processing GPO: $gpoName (Backup ID: $backupId)"

        if (-not $WhatIf) {
            Import-GPO -BackupId $backupId -Path $BackupPath -MigrationTable $MigTablePath -CreateIfNeeded $true
            Write-Host "Successfully imported: $gpoName" -ForegroundColor Green
        }
        else {
            Write-Host "WhatIf: Would import $gpoName" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Failed to import GPO: $_"
    }
}
