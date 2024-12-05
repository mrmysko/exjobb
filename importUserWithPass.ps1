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
    
    return $sb.ToString() -replace '[^a-zA-Z0-9\-]', ''
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
    } catch {
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
    } catch {
        Write-Error "Error creating Department Group $groupName : $_"
        return $null
    }
}

function Get-DomainPasswordPolicy {
    try {
        $policy = Get-ADDefaultDomainPasswordPolicy
        return $policy
    } catch {
        Write-Error "Unable to retrieve domain password policy: $_"
        return $null
    }
}

function Generate-CompliantPassword {
    param (
        [int]$MinLength = 8,
        [bool]$RequireUppercase = $true,
        [bool]$RequireLowercase = $true,
        [bool]$RequireNumber = $true,
        [bool]$RequireSpecialCharacter = $true
    )
    
    $uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $lowercase = "abcdefghijklmnopqrstuvwxyz"
    $numbers = "0123456789"
    $specialChars = "!@#$%^&*()-_=+[]{}|;:,.<>?/"

    $passwordChars = @()
    if ($RequireUppercase) { $passwordChars += $uppercase }
    if ($RequireLowercase) { $passwordChars += $lowercase }
    if ($RequireNumber) { $passwordChars += $numbers }
    if ($RequireSpecialCharacter) { $passwordChars += $specialChars }

    # Ensure the generated password meets the minimum length and contains at least one of each required character set
    do {
        $password = -join ((1..$MinLength) | ForEach-Object { $passwordChars | Get-Random })
        $valid = $true
        if ($RequireUppercase -and ($password -notmatch '[A-Z]')) { $valid = $false }
        if ($RequireLowercase -and ($password -notmatch '[a-z]')) { $valid = $false }
        if ($RequireNumber -and ($password -notmatch '\d')) { $valid = $false }
        if ($RequireSpecialCharacter -and ($password -notmatch '[!@#$%^&*()\-_=+[\]{}|;:,.<>?/\\]')) { $valid = $false }
    } while (-not $valid)

    return $password
}

# Retrieve domain password policy
$passwordPolicy = Get-DomainPasswordPolicy
if ($passwordPolicy) {
    $minLength = $passwordPolicy.MinPasswordLength
    $requireUppercase = $passwordPolicy.ComplexityEnabled
    $requireLowercase = $passwordPolicy.ComplexityEnabled
    $requireNumber = $passwordPolicy.ComplexityEnabled
    $requireSpecialCharacter = $passwordPolicy.ComplexityEnabled
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
                $password = Generate-CompliantPassword -MinLength $minLength -RequireUppercase $requireUppercase -RequireLowercase $requireLowercase -RequireNumber $requireNumber -RequireSpecialCharacter $requireSpecialCharacter
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
    
    Write-Host "`nUser import and group assignments completed successfully!"
} catch {
    Write-Error "An error occurred during user import: $_"
}
