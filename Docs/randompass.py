import csv
import string
import random


# Function to generate a random password
def id_generator(
    size=8, chars=string.ascii_uppercase + string.ascii_lowercase + string.digits
):
    return "".join(random.choice(chars) for _ in range(size))


# Open the input CSV for reading and output CSV for writing
with open("./users.csv", "r") as csvinput:
    with open("./userpass.csv", "w", newline="") as csvoutput:
        writer = csv.writer(csvoutput, lineterminator="\n")
        reader = csv.reader(csvinput)

        all_rows = []

        # Add header for the new column (Password)
        first_row = next(reader)
        first_row.append("password")  # Add "Password" header for the new column
        all_rows.append(first_row)

        # Process each subsequent row and add a generated password
        for row in reader:
            row.append(id_generator())  # Add a password for each user
            all_rows.append(row)

        # Write all rows (including header) to the output CSV
        writer.writerows(all_rows)
