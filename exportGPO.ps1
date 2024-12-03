param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationDomain,
    
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = (Join-Path $PSScriptRoot "GPOBackup"),
    
    [Parameter(Mandatory = $false)]
    [string]$MigTablePath = (Join-Path $PSScriptRoot "gpo-migration.migtable")
)

# Create backup directory if it doesn't exist
if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force
}

# Get current domain
$sourceDomain = (Get-ADDomain).DNSRoot

# Get all tier-based admin groups from AD
$tierGroups = Get-ADGroup -Filter { Name -like "T*_Admins" } | Select-Object -ExpandProperty Name

# Generate Migration Table
$xmlStart = @"
<?xml version="1.0" encoding="utf-8"?>
<MigrationTable xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns="http://www.microsoft.com/GroupPolicy/GPOOperations/MigrationTable">
    <Mapping>
        <Type>User</Type>
        <Source>$sourceDomain\Domain Users</Source>
        <Destination>$DestinationDomain\Domain Users</Destination>
    </Mapping>
    <Mapping>
        <Type>User</Type>
        <Source>$sourceDomain\Administrator</Source>
        <Destination>$DestinationDomain\Administrator</Destination>
    </Mapping>
    <Mapping>
        <Type>Computer</Type>
        <Source>$sourceDomain\Domain Computers</Source>
        <Destination>$DestinationDomain\Domain Computers</Destination>
    </Mapping>
    <Mapping>
        <Type>Group</Type>
        <Source>$sourceDomain\Domain Admins</Source>
        <Destination>$DestinationDomain\Domain Admins</Destination>
    </Mapping>
"@

$tierMappings = $tierGroups | ForEach-Object {
    @"
    <Mapping>
        <Type>Group</Type>
        <Source>$sourceDomain\$_</Source>
        <Destination>$DestinationDomain\$_</Destination>
    </Mapping>
"@
}

$xmlEnd = @"
    <Mapping>
        <Type>UNCPath</Type>
        <Source>\\$sourceDomain\SYSVOL</Source>
        <Destination>\\$DestinationDomain\SYSVOL</Destination>
    </Mapping>
</MigrationTable>
"@

$finalXml = $xmlStart + [System.Environment]::NewLine + 
            ($tierMappings -join [System.Environment]::NewLine) + 
[System.Environment]::NewLine + $xmlEnd

# Save migration table
$finalXml | Out-File -FilePath $MigTablePath -Encoding UTF8

# Export GPOs
Write-Host "Exporting GPOs..."
$gpos = Get-GPO -All
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = Join-Path $BackupPath "GPOReport_$timestamp.html"

# Export HTML report of all GPOs
try {
    Get-GPOReport -All -ReportType HTML -Path $reportPath
    Write-Host "Successfully exported GPO report to: $reportPath" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to export GPO report: $_"
}

# Backup all GPOs
try {
    $backupResult = Backup-GPO -All -Path $BackupPath
    Write-Host "Successfully backed up GPOs to: $BackupPath" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to backup GPOs: $_"
}

# Output results
Write-Host "`nExport Summary:"
Write-Host "===================="
Write-Host "Source domain: $sourceDomain"
Write-Host "Migration table saved to: $MigTablePath"
Write-Host "GPO backup location: $BackupPath"
Write-Host "GPO HTML report: $reportPath"
Write-Host "`nDiscovered tier groups:"
$tierGroups | ForEach-Object { Write-Host "- $_" }
Write-Host "`nExported GPOs:"
$backupResult | ForEach-Object { Write-Host "- $($_.DisplayName)" }

# Create a manifest file with export details
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
- GPO Report: $reportPath

Tier Groups:
$($tierGroups | ForEach-Object { "- $_" })

Exported GPOs:
$($backupResult | ForEach-Object { "- $($_.DisplayName)" })
"@

$manifestPath = Join-Path $BackupPath "ExportManifest.txt"
$manifestContent | Out-File -FilePath $manifestPath

Write-Host "`nManifest file created at: $manifestPath"
Write-Host "Export process complete!"