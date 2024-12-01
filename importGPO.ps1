# Extract and copy GPO template files to SYSVOL PolicyDefinitions directory
param(
    [Parameter(Mandatory = $false)]
    [string]$ZipPath = ".\GPOs.zip",
    
    [Parameter(Mandatory = $false)]
    [string]$TempExtractPath = ".\GPOsTemp"
)

try {
    # Import Active Directory module
    Import-Module ActiveDirectory

    # Get domain information
    $domain = Get-ADDomain
    $domainName = $domain.DNSRoot

    # Define SYSVOL paths
    $sysvolPolicyPath = "\\$domainName\SYSVOL\$domainName\Policies"
    $policyDefinitionsPath = Join-Path $sysvolPolicyPath "PolicyDefinitions"
    $languagePath = Join-Path $policyDefinitionsPath "en-US"

    # Create directories if they don't exist
    if (-not (Test-Path $policyDefinitionsPath)) {
        New-Item -Path $policyDefinitionsPath -ItemType Directory -Force
        Write-Host "Created PolicyDefinitions directory at $policyDefinitionsPath"
    }

    if (-not (Test-Path $languagePath)) {
        New-Item -Path $languagePath -ItemType Directory -Force
        Write-Host "Created en-US language directory at $languagePath"
    }

    # Extract the zip file
    Write-Host "Extracting GPO templates from $ZipPath"
    Expand-Archive -Path $ZipPath -DestinationPath $TempExtractPath -Force

    # Copy the ADMX file
    $admxSource = Join-Path $TempExtractPath "GPOs\Ubuntu-all.admx"
    Copy-Item -Path $admxSource -Destination $policyDefinitionsPath -Force
    Write-Host "Copied Ubuntu-all.admx to $policyDefinitionsPath"

    # Copy the ADML file
    $admlSource = Join-Path $TempExtractPath "GPOs\Ubuntu-all.adml"
    Copy-Item -Path $admlSource -Destination $languagePath -Force
    Write-Host "Copied Ubuntu-all.adml to $languagePath"

    # Clean up temporary files
    Remove-Item -Path $TempExtractPath -Recurse -Force
    Write-Host "Cleaned up temporary files"

    Write-Host "`nGPO templates successfully copied to SYSVOL!"
}
catch {
    Write-Error "An error occurred while copying GPO templates: $_"
}
finally {
    # Ensure cleanup of temp directory even if an error occurred
    if (Test-Path $TempExtractPath) {
        Remove-Item -Path $TempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}