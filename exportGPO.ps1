param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationDomain,
    
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = ".\GPOBackup",
    
    [Parameter(Mandatory = $false)]
    [string]$MigTablePath = ".\gpo-migration.migtable"
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

# Get all tier-based admin groups from AD and their group types
$tierGroups = Get-ADGroup -Filter { Name -like "T*_Admins" } | Select-Object Name, GroupCategory, GroupScope

# Generate Migration Table with exact format
$migrationTable = @"
<?xml version="1.0" encoding="utf-16"?>
<MigrationTable xmlns:xsd="http://www.w3.org/2001/XMLSchema" 
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns="http://www.microsoft.com/GroupPolicy/GPOOperations/MigrationTable">
"@

# Add standard domain mappings with correct group types
$standardMappings = @(
    @{ Type = "User"; Source = "Administrator"; Destination = "Administrator" },
    @{ Type = "User"; Source = "Domain Users"; Destination = "Domain Users" },
    @{ Type = "Computer"; Source = "Domain Computers"; Destination = "Domain Computers" },
    @{ Type = "GlobalGroup"; Source = "Domain Admins"; Destination = "Domain Admins" }
)

foreach ($mapping in $standardMappings) {
    $migrationTable += @"
    <Mapping>
        <Type>$($mapping.Type)</Type>
        <Source>$($mapping.Source)</Source>
        <Destination>$($mapping.Destination)</Destination>
    </Mapping>
"@
}

# Add tier group mappings with correct group type
foreach ($group in $tierGroups) {
    # Convert AD GroupScope to migration table group type
    $groupType = switch ($group.GroupScope) {
        "Global" { "GlobalGroup" }
        "Universal" { "UniversalGroup" }
        "DomainLocal" { "LocalGroup" }
        default { "GlobalGroup" } # Default fallback
    }
    
    $migrationTable += @"
    <Mapping>
        <Type>$groupType</Type>
        <Source>$($group.Name)</Source>
        <Destination>$($group.Name)</Destination>
    </Mapping>
"@
}

# Add UNC path mapping
$migrationTable += @"
    <Mapping>
        <Type>UNCPath</Type>
        <Source>\\$sourceDomain\SYSVOL</Source>
        <Destination>\\$DestinationDomain\SYSVOL</Destination>
    </Mapping>
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
Write-Host "`nDiscovered tier groups:"
$tierGroups | ForEach-Object { Write-Host "- $($_.Name) ($($_.GroupScope))" }
Write-Host "`nExported GPOs:"
$backupResult | ForEach-Object { Write-Host "- $($_.DisplayName)" }

# Create a manifest file
$manifestContent = @"
GPO Export Manifest
==================
Export Date: $(Get-Date)
Source Domain: $sourceDomain
Destination Domain: $DestinationDomain
Number of GPOs: $($gpos.Count)
Number of Tier Groups: $($tierGroups.Count)

Files:
- Migration Table: $MigTablePath
- GPO Backup: $BackupPath
- GPO Report: $ReportPath
"@

$manifestContent | Out-File -FilePath (Join-Path $BackupPath "ExportManifest.txt")