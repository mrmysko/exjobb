param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationDomain,
    
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = ".\\GPOBackup",
    
    [Parameter(Mandatory = $false)]
    [string]$MigTablePath = ".\\gpo-migration.migtable"
)

# Convert to absolute paths using current directory
$BackupPath = Join-Path $PWD.Path "GPOBackup"
$MigTablePath = Join-Path $PWD.Path "gpo-migration.migtable"
$ReportPath = Join-Path $PWD.Path "GPOReport.html"

# Create backup directory if it doesn't exist
if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force
}

# Get current domain
$sourceDomain = (Get-ADDomain).DNSRoot

# Get all AD groups with their SIDs
$allGroups = Get-ADGroup -Filter * | Select-Object Name, SID

# Generate Migration Table with group names and SIDs
$migrationTable = @"
<?xml version="1.0" encoding="utf-16"?>
<MigrationTable xmlns:xsd="http://www.w3.org/2001/XMLSchema" 
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns="http://www.microsoft.com/GroupPolicy/GPOOperations/MigrationTable">
"@

foreach ($group in $allGroups) {
    $migrationTable += @"
    <Mapping>
        <Type>GlobalGroup</Type>
        <Source>$($group.SID)</Source>
        <Destination>$($group.Name)</Destination>
    </Mapping>
"@
}

$migrationTable += @"
</MigrationTable>
"@

# Save migration table using UTF-16 encoding
[System.IO.File]::WriteAllText($MigTablePath, $migrationTable, [System.Text.Encoding]::Unicode)

# Export GPOs
Write-Host "Exporting GPOs..."
$gpos = Get-GPO -All

# Export HTML report of all GPOs
Get-GPOReport -All -ReportType HTML -Path $ReportPath

# Backup all GPOs
$backupResult = Backup-GPO -All -Path $BackupPath

# Output results
Write-Host "`nExport Summary:"
Write-Host "===================="
Write-Host "Source domain: $sourceDomain"
Write-Host "Migration table saved to: $MigTablePath"
Write-Host "GPO backup location: $BackupPath"
Write-Host "GPO HTML report: $ReportPath"

# Create a manifest file
$manifestContent = @"
GPO Export Manifest
==================
Export Date: $(Get-Date)
Source Domain: $sourceDomain
Destination Domain: $DestinationDomain

Files:
- Migration Table: $MigTablePath
- GPO Backup: $BackupPath
- GPO Report: $ReportPath
"@

$manifestContent | Out-File -FilePath (Join-Path $BackupPath "ExportManifest.txt")
