param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,
    
    [Parameter(Mandatory = $false)]
    [string]$MigTablePath = ".\gpo-migration.migtable",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# Verify paths exist
if (-not (Test-Path $BackupPath)) {
    throw "Backup path not found: $BackupPath"
}

if (-not (Test-Path $MigTablePath)) {
    throw "Migration table not found: $MigTablePath"
}

# Function to get a valid GPO name
function Get-ValidGPOName {
    param($OriginalName)
    $name = $OriginalName
    $counter = 1
    while (Get-GPO -Name $name -ErrorAction SilentlyContinue) {
        $name = "$OriginalName($counter)"
        $counter++
    }
    return $name
}

# Import all GPOs
Write-Host "Starting GPO import process..."
Write-Host "Using backup path: $BackupPath"
Write-Host "Using migration table: $MigTablePath"

# Get all backup folders
$backupFolders = Get-ChildItem -Path $BackupPath -Directory | Where-Object { $_.Name -match '^[{]?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}[}]?$' }

$results = @{
    Successful = @()
    Failed     = @()
}

foreach ($folder in $backupFolders) {
    # Get GPO backup info
    try {
        $backupInfo = Import-GPO -Path $BackupPath -BackupId $folder.Name -WhatIf:$WhatIf -CreateIfNeeded -ErrorAction Stop
        $originalName = $backupInfo.BackupGpoName
        $targetName = Get-ValidGPOName -OriginalName $originalName

        # Import the GPO
        Write-Host "`nImporting GPO: $originalName"
        Write-Host "Target name: $targetName"
        
        if (-not $WhatIf) {
            $importedGPO = Import-GPO -BackupId $folder.Name -TargetName $targetName -Path $BackupPath -MigrationTable $MigTablePath
            Write-Host "Successfully imported GPO: $($importedGPO.DisplayName)" -ForegroundColor Green
            $results.Successful += @{
                OriginalName = $originalName
                NewName      = $importedGPO.DisplayName
                ID           = $importedGPO.Id
            }
        }
        else {
            Write-Host "WhatIf: Would import GPO: $targetName" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Failed to import GPO from backup folder $($folder.Name)"
        Write-Warning "Error: $_"
        $results.Failed += @{
            BackupFolder = $folder.Name
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
$($results.Successful | ForEach-Object { "- Original Name: $($_.OriginalName)`n  New Name: $($_.NewName)`n  ID: $($_.ID)`n" })

Failed Imports:
$($results.Failed | ForEach-Object { "- Backup Folder: $($_.BackupFolder)`n  Error: $($_.Error)`n" })
"@

$reportPath = "GPOImportReport_$timestamp.txt"
$reportContent | Out-File -FilePath $reportPath

# Summary
Write-Host "`n==========================="
Write-Host "Import Process Complete"
Write-Host "==========================="
Write-Host "Successfully imported: $($results.Successful.Count) GPOs"
Write-Host "Failed imports: $($results.Failed.Count) GPOs"
Write-Host "Detailed report saved to: $reportPath"