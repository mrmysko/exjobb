param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath
)

Import-Module ActiveDirectory

function Remove-SpecialCharacters {
    param(
        [string]$String
    )
    # Remove special characters and diacritics
    $normalized = $String.Normalize('FormD')
    $sb = New-Object System.Text.StringBuilder
    
    for ($i = 0; $i -lt $normalized.Length; $i++) {
        $c = $normalized[$i]
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    
    return $sb.ToString() -replace '[^a-zA-Z0-9]', ''
}

function Create-DepartmentOU {
    param(
        [string]$DepartmentName,
        [string]$GroupsPath,
        [bool]$EnableDeleteProtection = $true
    )
    
    try {
        $ouPath = "OU=$DepartmentName,$GroupsPath"
        $ouExists = Get-ADOrganizationalUnit -Filter "Name -eq '$DepartmentName'" -SearchBase $GroupsPath -SearchScope OneLevel -ErrorAction SilentlyContinue
        
        if (-not $ouExists) {
            New-ADOrganizationalUnit -Name $DepartmentName -Path $GroupsPath -ProtectedFromAccidentalDeletion $EnableDeleteProtection
            Write-Host "Created Department OU: $DepartmentName"
        }
        return $ouPath
    }
    catch {
        Write-Error "Error creating Department OU $DepartmentName : $_"
        return $null
    }
}

function Create-DepartmentGroup {
    param(
        [string]$DepartmentName,
        [string]$OUPath
    )
    
    try {
        $groupName = "$DepartmentName"
        $groupExists = Get-ADGroup -Filter "Name -eq '$groupName'" -SearchBase $OUPath -SearchScope OneLevel -ErrorAction SilentlyContinue
        
        if (-not $groupExists) {
            New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path $OUPath
            Write-Host "Created Department Group: $groupName"
        }
        return $groupName
    }
    catch {
        Write-Error "Error creating Department Group $groupName : $_"
        return $null
    }
}

try {
    # Get domain information
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $domainName = $domain.DNSRoot
    
    # Construct the paths for the new structure
    $usersOUPath = "OU=Users,OU=Tier Base,$domainDN"
    $groupsOUPath = "OU=Groups,OU=Tier Base,$domainDN"
    
    # Verify the OUs exist
    try {
        Get-ADOrganizationalUnit $usersOUPath
        Get-ADOrganizationalUnit $groupsOUPath
    }
    catch {
        Write-Error "Required OUs not found. Please run CreateOU.ps1 first."
        exit 1
    }
    
    # Import CSV
    $users = Import-Csv -Path $CsvPath
    
    # Create a hashtable to track departments and their groups
    $departmentGroups = @{}
    
    # First pass: Create department OUs and groups
    $users | ForEach-Object {
        $departments = $_.department -split '\s+'
        foreach ($dept in $departments) {
            if (-not $departmentGroups.ContainsKey($dept)) {
                $ouPath = Create-DepartmentOU -DepartmentName $dept -GroupsPath $groupsOUPath
                if ($ouPath) {
                    $groupName = Create-DepartmentGroup -DepartmentName $dept -OUPath $ouPath
                    if ($groupName) {
                        $departmentGroups[$dept] = $groupName
                    }
                }
            }
        }
    }
    
    # Second pass: Create users
    foreach ($user in $users) {
        # Clean the names and create UPN
        $cleanFirstName = Remove-SpecialCharacters -String $user.firstname
        $cleanLastName = Remove-SpecialCharacters -String $user.surname
        $upnPrefix = "$cleanFirstName$($cleanLastName.Substring(0,2))".ToLower()
        $upn = "$upnPrefix@$domainName"
        
        # Create display name and sam account name
        $displayName = "$($user.firstname) $($user.surname)"
        $samAccountName = $upnPrefix
        
        # Check if user already exists
        $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -ErrorAction SilentlyContinue
        
        if ($existingUser) {
            Write-Host "User $displayName already exists, updating group memberships..."
            $adUser = $existingUser
        }
        else {
            # Create new user
            try {
                $newUserParams = @{
                    Name = $displayName
                    GivenName = $user.firstname
                    Surname = $user.surname
                    DisplayName = $displayName
                    SamAccountName = $samAccountName
                    UserPrincipalName = $upn
                    Path = $usersOUPath
                    Department = $user.department
                    City = $user.city
                    OfficePhone = $user.phone
                    Enabled = $true
                    ChangePasswordAtLogon = $true
                    AccountPassword = (ConvertTo-SecureString "Welcome123!" -AsPlainText -Force)
                }
                
                $adUser = New-ADUser @newUserParams -PassThru
                Write-Host "Created user: $displayName with UPN: $upn"
            }
            catch {
                Write-Error "Error creating user $displayName : $_"
                continue
            }
        }
        
        # Add user to department groups
        $departments = $user.department -split '\s+'
        foreach ($dept in $departments) {
            if ($departmentGroups.ContainsKey($dept)) {
                try {
                    Add-ADGroupMember -Identity $departmentGroups[$dept] -Members $adUser.SamAccountName -ErrorAction SilentlyContinue
                    Write-Host "Added $displayName to group $($departmentGroups[$dept])"
                }
                catch {
                    Write-Error "Error adding $displayName to group $($departmentGroups[$dept]): $_"
                }
            }
        }
    }
    
    Write-Host "`nUser import and group assignments completed successfully!"
}
catch {
    Write-Error "An error occurred during user import: $_"
}