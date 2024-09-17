# Server Setup Automation Scripts (Laravel Backend and Vue.js Frontend)

This repository contains Bash scripts to automate the setup of various server components for a web development environment, specifically tailored for Laravel backend and Vue.js frontend projects. The scripts facilitate the configuration of Apache virtual hosts and MySQL databases.

## Current Scripts

1. **Apache Virtual Host Generator (`generate_vhosts.sh`):** This script generates Apache virtual host configurations based on user input. It can also read values from a `.env` file for automatic configuration if available.

2. **MySQL Database and User Generator (`create_mysql_db.sh`):** This script creates a new MySQL user and database, also based on user input. It can also read values from a `.env` file for automatic configuration if available.

3. **Project Setup (`setup_project.sh`)** This script automates the setup of a web development environment by combining the functionalities of `generate_vhosts.sh` and `create_mysql_db.sh`. It sets up both Apache virtual hosts and MySQL databases for Laravel backend and Vue.js frontend repositories. Additionally, it sets up the backend repository with required dependencies, database credentials, and performs database migration.

## Pre-requisites

The scripts need to be run on a system with Apache and MySQL installed, and with root privileges as they write to system directories and modify system configurations.

## Usage

1. Download the script files to your local machine.

2. **Important: Copy the contents of `config.example.txt` and save it as `.env` with the correct values.** Replace the placeholders with the actual values for your setup. Here's the format of the `.env` file:

   ```plaintext
   BACKEND_DOMAIN_NAME=your_backend_domain
   BACKEND_SITE_PATH=your_backend_path
   FRONTEND_DOMAIN_NAME=your_frontend_domain
   FRONTEND_SITE_PATH=your_frontend_path
   MYSQL_USERNAME=your_MYSQL_USERNAME
   MYSQL_PASSWORD=your_MYSQL_PASSWORD
   MYSQL_DATABASE=your_MYSQL_DATABASE
   MYSQL_HOST=your_MYSQL_HOST
   ```

   Replace `your_backend_domain`, `your_backend_path`, `your_frontend_domain`, `your_frontend_path`, `your_MYSQL_USERNAME`, `your_MYSQL_PASSWORD`, `your_MYSQL_DATABASE`, and `your_MYSQL_HOST` with the actual values.

3. Make the scripts executable with the following commands:

   ```bash
   chmod +x generate_vhosts.sh
   chmod +x create_mysql_db.sh
   chmod +x setup_project.sh
   ```

4. Run the scripts with root privileges:

   ```bash
   sudo ./generate_vhosts.sh
   sudo ./create_mysql_db.sh
   sudo ./setup_project.sh
   ```

   For both `generate_vhosts.sh` and `create_mysql_db.sh`, if the `.env` file is present and contains values, the scripts will read from the file and skip the interactive prompts. If the `.env` file is empty or missing any values, the scripts will prompt the user for input for the missing values.

   For `setup_project.sh`, it will automatically use the values from the `.env` file and perform the following tasks:
   - Clone or pull the backend (Laravel) repository using a personal access token.
   - Install backend dependencies, set up the database, and perform migrations.
   - Clone or pull the frontend repository and install frontend dependencies.

5. After running the scripts, the Apache configurations will be saved in `/etc/apache2/sites-available/` and the MySQL user and database will be created.

## Important Note

Don't forget to enable the newly created Apache virtual hosts using `a2ensite` and reload or restart Apache to apply the changes. If necessary, you can use the following commands:

To enable the Apache virtual hosts:

```bash
sudo a2ensite your_domain_name.conf
sudo systemctl restart apache2
```

Please note that these scripts automate the setup process for your Laravel backend and Vue.js frontend web development environment. Ensure that you have reviewed and updated the `.env` file with the correct values before running the scripts.
