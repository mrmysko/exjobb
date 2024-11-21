param(
    [Parameter(Mandatory = $true)]
    [string]$CompanyName,
    
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

try {
    # Get domain information
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $domainName = $domain.DNSRoot
    
    # Construct the target OU path
    $usersOUPath = "OU=Users,OU=Tier Base,OU=$CompanyName,$domainDN"
    
    # Verify the OU exists
    try {
        Get-ADOrganizationalUnit $usersOUPath
    }
    catch {
        Write-Error "Target OU not found: $usersOUPath"
        exit 1
    }
    
    # Import CSV
    $users = Import-Csv -Path $CsvPath
    
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
            Write-Host "User $displayName already exists, skipping..."
            continue
        }
        
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
                Office = $user.city
                OfficePhone = $user.phone
                Enabled = $true
                ChangePasswordAtLogon = $true
                AccountPassword = (ConvertTo-SecureString "Welcome123!" -AsPlainText -Force)
            }
            
            New-ADUser @newUserParams
            Write-Host "Created user: $displayName with UPN: $upn"
        }
        catch {
            Write-Error "Error creating user $displayName : $_"
        }
    }
    
    Write-Host "`nUser import completed successfully!"
}
catch {
    Write-Error "An error occurred during user import: $_"
}