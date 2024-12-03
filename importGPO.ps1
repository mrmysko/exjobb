param(
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = ".\GPOBackup",
    
    [Parameter(Mandatory = $false)]
    [string]$MigTablePath = ".\gpo-migration.migtable",
    
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

# Function to read GPO name from backup
function Get-GPONameFromBackup {
    param($BackupFolderPath)
    
    $backupXmlPath = Join-Path $BackupFolderPath "Backup.xml"
    if (Test-Path $backupXmlPath) {
        try {
            [xml]$backupInfo = Get-Content $backupXmlPath -ErrorAction Stop
            return $backupInfo.GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.DisplayName.InnerText
        }
        catch {
            Write-Warning "Error reading backup XML: $_"
            return $null
        }
    }
    return $null
}

# Get all backup folders
$backupFolders = Get-ChildItem -Path $BackupPath -Directory | 
Where-Object { $_.Name -match '^[{]?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}[}]?$' }

$results = @{
    Successful = @()
    Failed     = @()
}

foreach ($folder in $backupFolders) {
    try {
        # Get original GPO name from backup
        $gpoName = Get-GPONameFromBackup -BackupFolderPath $folder.FullName
        
        if (-not $gpoName) {
            Write-Warning "Could not determine GPO name for backup folder: $($folder.Name)"
            continue
        }

        Write-Host "`nProcessing GPO: $gpoName (Backup ID: $($folder.Name))"
        
        if (-not $WhatIf) {
            $importParams = @{
                BackupId       = $folder.Name
                TargetName     = $gpoName
                Path           = $BackupPath
                MigrationTable = $MigTablePath
                CreateIfNeeded = $true
            }
            
            $importedGpo = Import-GPO @importParams
            Write-Host "Successfully imported GPO: $gpoName" -ForegroundColor Green
            $results.Successful += @{
                Name     = $gpoName
                BackupId = $folder.Name
                NewId    = $importedGpo.Id
            }
        }
        else {
            Write-Host "WhatIf: Would import GPO: $gpoName" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Failed to import GPO from folder $($folder.Name)"
        Write-Warning "Error: $_"
        $results.Failed += @{
            BackupFolder = $folder.Name
            GPOName      = $gpoName
            Error        = $_.Exception.Message
        }
    }
}

# Generate report
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportContent = @"
GPO Import Report
================
Import Date: $(Get-Date)
Backup Path: $BackupPath
Migration Table: $MigTablePath
WhatIf Mode: $WhatIf

Successfully Imported GPOs:
$($results.Successful | ForEach-Object { "- GPO Name: $($_.Name)`n  Backup ID: $($_.BackupId)`n  New GPO ID: $($_.NewId)`n" })

Failed Imports:
$($results.Failed | ForEach-Object { "- GPO Name: $($_.GPOName)`n  Backup Folder: $($_.BackupFolder)`n  Error: $($_.Error)`n" })
"@

$reportPath = Join-Path $BackupPath "ImportReport_$timestamp.txt"
$reportContent | Out-File -FilePath $reportPath

# Summary
Write-Host "`n==========================="
Write-Host "Import Process Complete"
Write-Host "==========================="
Write-Host "Successfully imported: $($results.Successful.Count) GPOs"
Write-Host "Failed imports: $($results.Failed.Count) GPOs"
Write-Host "Detailed report saved to: $reportPath"