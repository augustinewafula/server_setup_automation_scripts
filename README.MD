# Server Setup Automation Scripts

This repository contains Bash scripts to automate the setup of various server components, including Apache virtual hosts and MySQL databases.

## Current Scripts

1. **Apache Virtual Host Generator (generate_vhosts.sh):** This script generates Apache virtual host configurations based on user input.

2. **MySQL Database and User Generator (create_mysql_db.sh):** This script creates a new MySQL user and database, also based on user input.

## Pre-requisites

The scripts need to be run on a system with Apache and MySQL installed, and with root privileges as they write to system directories and modify system configurations.

## Usage

1. Download the script files to your local machine.

2. Make the scripts executable with the following commands:

    ```bash
    chmod +x generate_vhosts.sh
    chmod +x create_mysql_db.sh
    ```

3. Run the scripts with root privileges:

    ```bash
    sudo ./generate_vhosts.sh
    sudo ./create_mysql_db.sh
    ```

For `generate_vhosts.sh`, follow the interactive prompts to generate configurations for the frontend, backend, or both. You will need to provide the domain name and the document root path.

For `create_mysql_db.sh`, you will be asked for the username, password, database name, and host for the new MySQL user and database.

After running the scripts, the Apache configurations will be saved in `/etc/apache2/sites-available/` and the MySQL user and database will be created.

## Important Note

Don't forget to enable the newly created sites using `a2ensite` and reload or
