# Creates a basic tiered OU-structure

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

function Create-AdminGroup {
    param(
        [string]$Name,
        [string]$Path
    )
    
    try {
        $groupExists = Get-ADGroup -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel
        if (-not $groupExists) {
            New-ADGroup -Name $Name -GroupScope Global -GroupCategory Security -Path $Path
            Write-Host "Created Group: $Name in $Path"
        }
        else {
            Write-Host "Group already exists: $Name in $Path"
        }
    }
    catch {
        Write-Error ("Error creating/checking Group {0} in {1} - {2}" -f $Name, $Path, $_)
    }
}

try {
    $domainDN = (Get-ADDomain).DistinguishedName
    
    $companyPath = "OU=$CompanyName,$domainDN"
    Create-OUIfNotExists -Name $CompanyName -Path $domainDN
    
    Create-OUIfNotExists -Name "Tier Base" -Path $companyPath
    $basePath = "OU=Tier Base,$companyPath"
    
    Create-OUIfNotExists -Name "Users" -Path $basePath
    Create-OUIfNotExists -Name "Admins" -Path $basePath
    Create-OUIfNotExists -Name "Groups" -Path $basePath
    Create-OUIfNotExists -Name "Computers" -Path $basePath

    $computersPath = "OU=Computers,$basePath"
    Create-OUIfNotExists -Name "Windows" -Path $computersPath
    Create-OUIfNotExists -Name "Linux" -Path $computersPath
    
    Create-AdminGroup -Name "TB_Admins" -Path "OU=Groups,$basePath"
    
    for ($i = 0; $i -lt $NumberOfTiers; $i++) {
        $tierName = "Tier $i"
        Create-OUIfNotExists -Name $tierName -Path $companyPath
        $tierPath = "OU=$tierName,$companyPath"
        
        Create-OUIfNotExists -Name "Servers" -Path $tierPath
        Create-OUIfNotExists -Name "Admins" -Path $tierPath
        Create-OUIfNotExists -Name "Groups" -Path $tierPath

        $serversPath = "OU=Servers,$tierPath"
        Create-OUIfNotExists -Name "Windows" -Path $serversPath
        Create-OUIfNotExists -Name "Linux" -Path $serversPath
        
        # Create single tier admin group in Groups OU
        $groupsPath = "OU=Groups,$tierPath"
        Create-AdminGroup -Name "T${i}_Admins" -Path $groupsPath
    }
    
    Write-Host "`nOU structure creation completed successfully!"
    
}