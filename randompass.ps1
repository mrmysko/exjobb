# Function to generate a random password
function Generate-Password {
    param (
        [int]$Length = 8
    )

    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    $password = -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
    return $password
}

# Path to the input and output CSV files
$inputCsv = "./users.csv"
$outputCsv = "./userpass.csv"

# Read the input CSV file with proper encoding (UTF-8 or default to ensure no characters are lost)
$csvData = Import-Csv -Path $inputCsv -Encoding UTF8

# Prepare the header and add the "Password" column to each row
$csvData | ForEach-Object {
    $_ | Add-Member -MemberType NoteProperty -Name "password" -Value (Generate-Password)
}

# Export the modified data to a new CSV file with UTF-8 encoding to preserve characters
$csvData | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8
