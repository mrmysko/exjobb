param(
    [Parameter(Mandatory = $true)]
    [int]$NumberOfTiers,
    
    [Parameter()]
    [switch]$RemoveDeleteProtection
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
            New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion (-not $RemoveDeleteProtection)
            Write-Host "Created OU: $Name in $Path (Delete Protection: $(-not $RemoveDeleteProtection))"
        }
        else {
            Set-ADOrganizationalUnit -Identity "OU=$Name,$Path" -ProtectedFromAccidentalDeletion (-not $RemoveDeleteProtection)
            Write-Host "OU already exists: $Name in $Path (Updated Delete Protection: $(-not $RemoveDeleteProtection))"
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

function Add-ToDomainAdmins {
    param(
        [string]$GroupName
    )
    
    try {
        $isMember = Get-ADGroupMember -Identity "Domain Admins" | Where-Object { $_.Name -eq $GroupName }
        if (-not $isMember) {
            Add-ADGroupMember -Identity "Domain Admins" -Members $GroupName
            Write-Host "Added $GroupName to Domain Admins group"
        }
        else {
            Write-Host "$GroupName is already a member of Domain Admins group"
        }
    }
    catch {
        Write-Error ("Error adding {0} to Domain Admins - {1}" -f $GroupName, $_)
    }
}

try {
    # Get the domain information
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $rootDomain = $domain.DNSRoot
    Write-Host "Using domain: $rootDomain"
    
    # Create Admin OU at root level
    Create-OUIfNotExists -Name "Admin" -Path $domainDN
    $adminPath = "OU=Admin,$domainDN"
    
    # Create Tier Base at root level
    Create-OUIfNotExists -Name "Tier Base" -Path $domainDN
    $basePath = "OU=Tier Base,$domainDN"
    
    Create-OUIfNotExists -Name "Users" -Path $basePath
    Create-OUIfNotExists -Name "Groups" -Path $basePath
    Create-OUIfNotExists -Name "Computers" -Path $basePath
    $computersPath = "OU=Computers,$basePath"
    Create-OUIfNotExists -Name "Windows" -Path $computersPath
    Create-OUIfNotExists -Name "Linux" -Path $computersPath
    
    # Create Base Tier under root Admin OU
    Create-OUIfNotExists -Name "Tier Base" -Path $adminPath
    $baseAdminPath = "OU=Tier Base,$adminPath"
    Create-OUIfNotExists -Name "Groups" -Path $baseAdminPath
    Create-OUIfNotExists -Name "Admins" -Path $baseAdminPath
    Create-AdminGroup -Name "TB_Admins" -Path "OU=Groups,$baseAdminPath"
    
    # Create other tiers under Admin OU
    for ($i = 0; $i -lt $NumberOfTiers; $i++) {
        $tierName = "Tier $i"
        Create-OUIfNotExists -Name $tierName -Path $adminPath
        $tierPath = "OU=$tierName,$adminPath"
        
        Create-OUIfNotExists -Name "Servers" -Path $tierPath
        Create-OUIfNotExists -Name "Groups" -Path $tierPath
        Create-OUIfNotExists -Name "Admins" -Path $tierPath
        
        # Create Windows and Linux OUs under Servers
        $serversPath = "OU=Servers,$tierPath"
        Create-OUIfNotExists -Name "Windows" -Path $serversPath
        Create-OUIfNotExists -Name "Linux" -Path $serversPath
        
        # Create tier admin group
        Create-AdminGroup -Name "T${i}_Admins" -Path "OU=Groups,$tierPath"
        
        # If this is Tier 0, add the admin group to Domain Admins
        if ($i -eq 0) {
            Add-ToDomainAdmins -GroupName "T0_Admins"
        }
    }
    
    Write-Host "`nOU structure creation completed successfully!"
    Write-Host "Delete Protection is set to: $(-not $RemoveDeleteProtection)"
}
catch {
    Write-Error ("An error occurred during OU structure creation - {0}" -f $_)
}