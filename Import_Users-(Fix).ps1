[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    
    [Parameter(Mandatory = $true)]
    [string]$Domain,
    
    [Parameter(Mandatory = $false)]
    [string]$Encoding = 'UTF8',
    
    [Parameter(Mandatory = $false)]
    [string]$BaseOU = "OU=Users,OU=Tier Base"
)

function New-RandomPassword {
    # Generate arrays for password characters outside the loop
    $Upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray() | Get-Random -Count 3
    $Lower = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray() | Get-Random -Count 3
    $Digit = '0123456789'.ToCharArray() | Get-Random -Count 1
    $Special = '!"#¤%&/()?*^'.ToCharArray() | Get-Random -Count 1
    
    $Pass = $Upper + $Lower + $Digit + $Special | Sort-Object { Get-Random }
    return [string]::Concat($Pass)
}

function New-UniqueSAM {
    param(
        [string]$FirstName,
        [string]$LastName
    )
    
    # Handle names shorter than 2 characters
    $FirstPart = if ($FirstName.Length -ge 2) { $FirstName.Substring(0, 2) } else { $FirstName.PadRight(2, 'x') }
    $LastPart = if ($LastName.Length -ge 2) { $LastName.Substring(0, 2) } else { $LastName.PadRight(2, 'x') }
    
    # Convert to ASCII and handle special characters
    $SAMBase = [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("ISO-8859-1").GetBytes($FirstPart + $LastPart)).ToLower()
    
    # Try up to 89 times to generate a unique SAM (10-99)
    $counter = 10
    do {
        $SAM = $SAMBase + $counter
        $exists = Get-ADUser -Filter "SamAccountName -eq '$SAM'"
        if (-not $exists) {
            return $SAM
        }
        $counter++
    } while ($counter -lt 100)
    
    throw "Could not generate unique SAM for $FirstName $LastName"
}

function Get-DepartmentMapping {
    param([string]$Department)
    
    $mapping = @{
        "Säljare" = "Sales"
        "Konsult" = "Consultants"
        "Ekonom" = "Economy"
        "Ledning" = "Management"
    }
    
    return $mapping[$Department] ?? $Department
}

try {
    # Validate file exists
    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }
    
    # Import users
    $Users = Import-Csv -Delimiter ',' -Path $FilePath -Encoding $Encoding
    
    # Get domain components for OU path
    $DomainParts = $Domain -split '\.'
    $DomainDN = ($DomainParts | ForEach-Object { "DC=$_" }) -join ','
    $OUPath = "$BaseOU,OU=$Domain,$DomainDN"
    
    # Create department groups mapping for batch processing
    $DepartmentGroups = @{}
    
    foreach ($User in $Users) {
        $DisplayName = "$($User.firstname) $($User.surname)"
        
        # Generate password and SAM
        $Password = New-RandomPassword
        $SAM = New-UniqueSAM -FirstName $User.firstname -Surname $User.surname
        
        # Map department
        $Department = Get-DepartmentMapping -Department $User.department
        
        # Add properties to user object for export
        Add-Member -InputObject $User -NotePropertyName "password" -NotePropertyValue $Password -Force
        Add-Member -InputObject $User -NotePropertyName "SAM" -NotePropertyValue $SAM -Force
        
        # Create UPN
        $UPN = "$SAM@$Domain".ToLower()
        
        # Create secure password
        $SecurePass = ConvertTo-SecureString -String $Password -AsPlainText -Force
        
        # Create user
        New-ADUser -Name $DisplayName `
            -DisplayName $DisplayName `
            -SamAccountName $SAM `
            -UserPrincipalName $UPN `
            -GivenName $User.firstname `
            -Surname $User.surname `
            -AccountPassword $SecurePass `
            -Enabled $true `
            -Path $OUPath `
            -ChangePasswordAtLogon $true `
            -City $User.city `
            -StreetAddress $User.address `
            -PostalCode $User.postal `
            -Department $Department `
            -MobilePhone $User.phone
        
        # Add to department groups collection
        if (-not $DepartmentGroups.ContainsKey($Department)) {
            $DepartmentGroups[$Department] = @()
        }
        $DepartmentGroups[$Department] += $SAM
        
        Write-Host "Created user: $DisplayName ($SAM)"
    }
    
    # Batch add users to department groups
    foreach ($dept in $DepartmentGroups.Keys) {
        $groupName = "$Lang-$dept"
        if (Get-ADGroup -Filter "Name -eq '$groupName'") {
            Add-ADGroupMember -Identity $groupName -Members $DepartmentGroups[$dept]
            Write-Host "Added $($DepartmentGroups[$dept].Count) users to group $groupName"
        }
        else {
            Write-Warning "Group not found: $groupName"
        }
    }
    
    # Export updated user list with passwords and SAMs
    $Users | Select-Object * | Export-Csv $FilePath -Encoding $Encoding -NoTypeInformation
    Write-Host "Successfully exported updated user list to $FilePath"
}
catch {
    Write-Error "An error occurred: $_"
    Write-Error $_.ScriptStackTrace
}