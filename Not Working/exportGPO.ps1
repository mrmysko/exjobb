# Set error action preference and import required module
$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy

# Create timestamp for backup folder
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$backupPath = "C:\GPOBackups\$timestamp"

# Create backup directory if it doesn't exist
if (-not (Test-Path $backupPath)) {
    New-Item -ItemType Directory -Path $backupPath | Out-Null
}

# Start transcript for logging
Start-Transcript -Path "$backupPath\GPOExport_Log.txt"

try {
    # Get all GPOs in the domain
    $GPOs = Get-GPO -All

    # Export each GPO
    foreach ($GPO in $GPOs) {
        Write-Host "Backing up GPO: $($GPO.DisplayName)"
        
        try {
            Backup-GPO -Name $GPO.DisplayName -Path $backupPath
            
            # Export GPO report in XML format for migration
            Get-GPOReport -Name $GPO.DisplayName -ReportType XML -Path "$backupPath\$($GPO.DisplayName)_Report.xml"
        }
        catch {
            Write-Warning "Failed to backup GPO $($GPO.DisplayName): $_"
        }
    }

    # Create manifest file with domain info
    $domainInfo = Get-ADDomain
    @{
        'ExportDate'   = (Get-Date).ToString()
        'SourceDomain' = $domainInfo.DNSRoot
        'GPOCount'     = $GPOs.Count
    } | ConvertTo-Json | Out-File "$backupPath\manifest.json"

    Write-Host "GPO backup completed successfully. Backup location: $backupPath"
}
catch {
    Write-Error "Export failed: $_"
}
finally {
    Stop-Transcript
}