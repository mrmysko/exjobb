# Expects OU-structure to be in place.

$File_Path = '.\users.csv'
$Domain = 'dd.com'
$Encoding = 'UTF8'

# Add -Header is first row is missing. It will be added on export.
$Users = Import-Csv -Delimiter ',' -Path "$File_Path" -Encoding $Encoding

foreach ($User in $Users)            
{   
    $Display_Name = $User.firstname + ' ' + $User.surname

    # -Generate pass- 3 letters of upper and lowercase, 1 number, 1 special char and random sort them.
    $Upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray() | Get-Random -Count 3
    $Lower = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray() | Get-Random -Count 3
    $Digit = '0123456789'.ToCharArray() | Get-Random -Count 1
    $Special = '!"#¤%&/()?*^'.ToCharArray() | Get-Random -Count 1

    $Pass = $Upper+$Lower+$Digit+$Special | Sort-Object {Get-Random}
    $Pass = [string]::Concat($Pass)
    $Secure_Pass = ConvertTo-SecureString -String $Pass -AsPlainText -Force

    # Add new property with password to user.
    Add-Member -InputObject $User -NotePropertyName "password" -NotePropertyValue $Pass -Force

    # -Format SAM- Get two first letters in first and surname, and add two digits at the end.
    $Name_Numbers = (Get-Random -Minimum 10 -Maximum 99).ToString()
    $SAM = $($User.firstname.Substring(0,2) + $User.surname.Substring(0,2))
    $SAM = [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding(1251).GetBytes($SAM)).ToLower() + $Name_Numbers
    
    # Add new property with SAM to user.
    Add-Member -InputObject $User -NotePropertyName "SAM" -NotePropertyValue $SAM -Force

    # Remove accents, concatenate string, add a dot between names, add the numbers at the end and make everything lowercase.
    $UPN = ($SAM + '@' + $Domain).ToLower()

    $OU = "OU=Users,OU=Tier Base,OU=dd.com,DC=Labb,DC=se"

    New-ADUser -Name $Display_Name -DisplayName $Display_Name -SamAccountName $SAM -UserPrincipalName $UPN -GivenName $User.firstname -Surname $User.surname -AccountPassword $Secure_Pass -Enabled $true -Path $OU -ChangePasswordAtLogon $true -City $User.city -StreetAddress $User.address -PostalCode $User.postal -Department $User.department -MobilePhone $User.phone
    Add-ADGroupMember -Identity $($Lang + "-" + $User.department) -Members $SAM
}

$Users | Select-Object -Skip 1 * | Export-Csv $File_Path -Encoding $Encoding -NoTypeInformation

# TODO - Samla användarna i arrayer för grupperna istället och lägg till alla samtidigt.
# TODO - Generera arrays för lösen utanför loopen, det är onödigt att göra om dom för varje $User.
# TODO - Plocka ut domännamn i tld och second-level.
# Fel - SAM formatteringen funkar inte med namn med färre än 2 tecken.
# Fel - SAM formatteringen hanterar inte namn som är lika och råkar generera samma nummer.
# Fel - SAM formatteringen gör om cyrillics till ?.

# Importera för lösenordsgenerering.
# Add-Type -AssemblyName System.Web
# $Temp_Pass = [System.Web.Security.Membership]::GeneratePassword(8, 1) 

#    switch ( $User.department ) {
#        {$_ -eq "Säljare"} {
#            $User.department = "Sales"
#        }
#        {$_ -eq "Konsult"} {
#            $User.department = "Consultants"
#        }
#        {$_ -eq "Ekonom"} {
#            $User.department = "Economy"
#        }
#        {$_ -eq "Ledning"} {
#            $User.department = "Management"
#        }
#    }