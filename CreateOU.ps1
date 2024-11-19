# Create a basic OU structure.

param(
    [Parameter(Mandatory = $true)]
    [string]$CompanyName,
    
    [Parameter(Mandatory = $true)]
    [int]$NumberOfTiers
)

Import-Module ActiveDirectory

function Create-OUIfNotExists {
    param(
        [string]$Name,
        [string]$Path
    )
    
    try {
        $ouExists = Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel
        if (-not $ouExists) {
            New-ADOrganizationalUnit -Name $Name -Path $Path
            Write-Host "Created OU: $Name in $Path"
        }
        else {
            Write-Host "OU already exists: $Name in $Path"
        }
    }
    catch {
        Write-Error ("Error creating/checking OU {0} in {1} - {2}" -f $Name, $Path, $_)
    }
}

try {
    $domainDN = (Get-ADDomain).DistinguishedName
    
    $companyPath = "OU=$CompanyName,$domainDN"
    Create-OUIfNotExists -Name $CompanyName -Path $domainDN
    
    Create-OUIfNotExists -Name "Tier Base" -Path $companyPath
    $basePath = "OU=Tier Base,$companyPath"
    
    Create-OUIfNotExists -Name "Clients" -Path $basePath
    Create-OUIfNotExists -Name "Users" -Path $basePath
    Create-OUIfNotExists -Name "Admins" -Path $basePath
    Create-OUIfNotExists -Name "Groups" -Path $basePath
    
    for ($i = 1; $i -le $NumberOfTiers; $i++) {
        $tierName = "Tier $i"
        Create-OUIfNotExists -Name $tierName -Path $companyPath
        $tierPath = "OU=$tierName,$companyPath"
        
        Create-OUIfNotExists -Name "Servers" -Path $tierPath
        Create-OUIfNotExists -Name "Admins" -Path $tierPath
    }
    
    Write-Host "`nOU structure creation completed successfully!"
    
}
catch {
    Write-Error ("An error occurred during OU structure creation - {0}" -f $_)
}