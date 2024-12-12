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
    }
    catch {
        Write-Error "Error creating Department Group $groupName : $_"
        return $null
    }
}

function Generate-RandomPassword {
    param(
        [int]$Length = 14
    )
    
    # Ensure at least one character from each required set
    $uppercase = (Get-Random -InputObject ([char[]](65..90))) # A-Z
    $lowercase = (Get-Random -InputObject ([char[]](97..122))) # a-z
    $number = (Get-Random -InputObject ([char[]](48..57))) # 0-9
    $special = (Get-Random -InputObject ([char[]]"!@#$%^&*()-_=+[]{}|;:,.<>?/".ToCharArray()))
    
    # Calculate remaining length needed
    $remainingLength = $Length - 4
    
    # Generate remaining random characters
    $allChars = [char[]](65..90) + [char[]](97..122) + [char[]](48..57) + "!@#$%^&*()-_=+[]{}|;:,.<>?/".ToCharArray()
    $remainingChars = -join ((1..$remainingLength) | ForEach-Object { Get-Random -InputObject $allChars })
    
    # Combine all parts and shuffle
    $password = $uppercase + $lowercase + $number + $special + $remainingChars
    $passwordArray = $password.ToCharArray()
    $shuffledPassword = -join ($passwordArray | Get-Random -Count $passwordArray.Length)
    
    return $shuffledPassword
}

try {
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $domainName = $domain.DNSRoot
    
    $usersOUPath = "OU=Users,OU=Tier Base,$domainDN"
    $groupsOUPath = "OU=Groups,OU=Tier Base,$domainDN"
    
    $outputPath = Join-Path -Path $PSScriptRoot -ChildPath "userpass.csv"
    
    try {
        Get-ADOrganizationalUnit $usersOUPath
        Get-ADOrganizationalUnit $groupsOUPath
    }
    catch {
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

        if ($user.PSObject.Properties.Match('mail').Count -gt 0 -and $user.mail) {
            $mail = $user.mail
        }
        else {
            $mail = "$upnPrefix@$domainName"
        }
        
        $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -ErrorAction SilentlyContinue
        
        if ($existingUser) {
            Write-Host "User $displayName already exists, updating group memberships..."
            $adUser = $existingUser
        }
        else {
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
                    Mail                  = $mail
                    Enabled               = $true
                    ChangePasswordAtLogon = $true
                    AccountPassword       = (ConvertTo-SecureString -AsPlainText $password -Force)
                }
                
                $adUser = New-ADUser @newUserParams -PassThru
                Write-Host "Created user: $displayName with UPN: $upn"
                
                $userPasswordList += [PSCustomObject]@{
                    FirstName = $user.firstname
                    LastName  = $user.surname
                    UserName  = $samAccountName
                    Password  = $password
                    UPN       = $upn
                }
            }
            catch {
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
                }
                catch {
                    Write-Error "Error adding $displayName to group $($departmentGroups[$dept]): $_"
                }
            }
        }
    }
    
    # Export the password list to the same directory as the script
    if ($userPasswordList.Count -gt 0) {
        $userPasswordList | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "User and password information has been saved to $outputPath"
    }
    else {
        Write-Warning "No new users were created, userpass.csv was not generated"
    }
    
    Write-Host "`nUser import and group assignments completed successfully!"
}
catch {
    Write-Error "An error occurred during user import: $_"
}
