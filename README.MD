# Server Setup Automation Scripts

This repository contains Bash scripts to automate the setup of various server components, including Apache virtual hosts and MySQL databases.

## Current Scripts

1. **Apache Virtual Host Generator (`generate_vhosts.sh`):** This script generates Apache virtual host configurations based on user input. It can also read values from a `config.txt` file for automatic configuration if available.

2. **MySQL Database and User Generator (`create_mysql_db.sh`):** This script creates a new MySQL user and database, also based on user input. It can also read values from a `config.txt` file for automatic configuration if available.

## Pre-requisites

The scripts need to be run on a system with Apache and MySQL installed, and with root privileges as they write to system directories and modify system configurations.

## Usage

1. Download the script files to your local machine.

2. **Important: Update the `config.txt` file with the correct values.** The `config.txt` file will be provided in the repository. Open the `config.txt` file and replace the placeholders with the actual values for your setup. Here's the format of the `config.txt` file:

    ```plaintext
    backend_domain_name=your_backend_domain
    backend_site_path=your_backend_path
    frontend_domain_name=your_frontend_domain
    frontend_site_path=your_frontend_path
    mysql_username=your_mysql_username
    mysql_password=your_mysql_password
    mysql_database=your_mysql_database
    mysql_host=your_mysql_host
    ```

    Replace `your_backend_domain`, `your_backend_path`, `your_frontend_domain`, `your_frontend_path`, `your_mysql_username`, `your_mysql_password`, `your_mysql_database`, and `your_mysql_host` with the actual values.

3. Make the scripts executable with the following commands:

    ```bash
    chmod +x generate_vhosts.sh
    chmod +x create_mysql_db.sh
    ```

4. Run the scripts with root privileges:

    ```bash
    sudo ./generate_vhosts.sh
    sudo ./create_mysql_db.sh
    ```

    For both scripts, if the `config.txt` file is present and contains values, the scripts will read from the file and skip the interactive prompts. If the `config.txt` file is empty or missing any values, the scripts will prompt the user for input for the missing values.

    For `generate_vhosts.sh`, follow the interactive prompts to generate configurations for the frontend, backend, or both. You will need to provide the domain name and the document root path.

    For `create_mysql_db.sh`, you will be asked for the MySQL username, password, database name, and host if the values are not found in the `config.txt` file.

After running the scripts, the Apache configurations will be saved in `/etc/apache2/sites-available/` and the MySQL user and database will be created.

## Important Note

Don't forget to enable the newly created Apache virtual hosts using `a2ensite` and reload or restart Apache to apply the changes. If necessary, you can use the following commands:

To enable the Apache virtual hosts:

```bash
sudo a2ensite your_domain_name.conf
sudo systemctl restart apache2
