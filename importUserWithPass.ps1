param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath
)

Import-Module ActiveDirectory

function Remove-SpecialCharacters {
    param(
        [string]$String
    )
    $normalized = $String.Normalize('FormD')
    $sb = New-Object System.Text.StringBuilder
    
    for ($i = 0; $i -lt $normalized.Length; $i++) {
        $c = $normalized[$i]
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    
    return $sb.ToString() -replace '[^a-zA-Z0-9\-]', ''
}

function Create-DepartmentGroup {
    param(
        [string]$DepartmentName,
        [string]$GroupsOUPath
    )
    
    try {
        $groupName = "$DepartmentName"
        $groupExists = Get-ADGroup -Filter "Name -eq '$groupName'" -SearchBase $GroupsOUPath -SearchScope OneLevel -ErrorAction SilentlyContinue
        
        if (-not $groupExists) {
            New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path $GroupsOUPath
            Write-Host "Created Department Group: $groupName"
        }
        return $groupName
    } catch {
        Write-Error "Error creating Department Group $groupName : $_"
        return $null
    }
}

function Generate-RandomPassword {
    param(
        [int]$Length = 14
    )
    $uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $lowercase = "abcdefghijklmnopqrstuvwxyz"
    $numbers = "0123456789"
    $specialChars = "!@#$%^&*()-_=+[]{}|;:,.<>?/"

    $passwordChars = @($uppercase, $lowercase, $numbers, $specialChars) -join ""
    $password = -join ((1..$Length) | ForEach-Object { $passwordChars | Get-Random })
    
    # Ensure password meets complexity requirements
    while (
        ($password -notmatch '[A-Z]') -or
        ($password -notmatch '[a-z]') -or
        ($password -notmatch '\d') -or
        ($password -notmatch '[!@#$%^&*()\-_=+\[\]{}|;:,.<>?/]')
    ) {
        $password = -join ((1..$Length) | ForEach-Object { $passwordChars | Get-Random })
    }
    
    return $password
}

try {
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $domainName = $domain.DNSRoot
    
    $usersOUPath = "OU=Users,OU=Tier Base,$domainDN"
    $groupsOUPath = "OU=Groups,OU=Tier Base,$domainDN"
    
    try {
        Get-ADOrganizationalUnit $usersOUPath
        Get-ADOrganizationalUnit $groupsOUPath
    } catch {
        Write-Error "Required OUs not found. Please run CreateOU.ps1 first."
        exit 1
    }
    
    $users = Import-Csv -Path $CsvPath
    $departmentGroups = @{}
    $userPasswordList = @()
    
    foreach ($user in $users) {
        $departments = $user.department -split '\s+'
        foreach ($dept in $departments) {
            if (-not $departmentGroups.ContainsKey($dept)) {
                $groupName = Create-DepartmentGroup -DepartmentName $dept -GroupsOUPath $groupsOUPath
                if ($groupName) {
                    $departmentGroups[$dept] = $groupName
                }
            }
        }
    }
    
    foreach ($user in $users) {
        $cleanFirstName = Remove-SpecialCharacters -String $user.firstname
        $cleanLastName = Remove-SpecialCharacters -String $user.surname
        $upnPrefix = "$cleanFirstName$($cleanLastName.Substring(0,2))".ToLower()
        $upn = "$upnPrefix@$domainName"
        
        $displayName = "$($user.firstname) $($user.surname)"
        $samAccountName = $upnPrefix
        
        $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -ErrorAction SilentlyContinue
        
        if ($existingUser) {
            Write-Host "User $displayName already exists, updating group memberships..."
            $adUser = $existingUser
        } else {
            try {
                $password = Generate-RandomPassword -Length 14
                $newUserParams = @{
                    Name                  = $displayName
                    GivenName             = $user.firstname
                    Surname               = $user.surname
                    DisplayName           = $displayName
                    SamAccountName        = $samAccountName
                    UserPrincipalName     = $upn
                    Path                  = $usersOUPath
                    Department            = $user.department
                    City                  = $user.city
                    OfficePhone           = $user.phone
                    Enabled               = $true
                    ChangePasswordAtLogon = $true
                    AccountPassword       = (ConvertTo-SecureString -AsPlainText $password -Force)
                }
                
                $adUser = New-ADUser @newUserParams -PassThru
                Write-Host "Created user: $displayName with UPN: $upn"
                
                $userPasswordList += [PSCustomObject]@{
                    FirstName  = $user.firstname
                    LastName   = $user.surname
                    UserName   = $samAccountName
                    Password   = $password
                    UPN        = $upn
                }
            } catch {
                Write-Error "Error creating user $displayName : $_"
                continue
            }
        }
        
        $departments = $user.department -split '\s+'
        foreach ($dept in $departments) {
            if ($departmentGroups.ContainsKey($dept)) {
                try {
                    Add-ADGroupMember -Identity $departmentGroups[$dept] -Members $adUser.SamAccountName -ErrorAction SilentlyContinue
                    Write-Host "Added $displayName to group $($departmentGroups[$dept])"
                } catch {
                    Write-Error "Error adding $displayName to group $($departmentGroups[$dept]): $_"
                }
            }
        }
    }
    
    $userPasswordList | Export-Csv -Path "./userpass.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "User and password information has been saved to userpass.csv"
    Write-Host "`nUser import and group assignments completed successfully!"
} catch {
    Write-Error "An error occurred during user import: $_"
}
