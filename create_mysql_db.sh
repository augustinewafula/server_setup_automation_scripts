#!/bin/bash

CONFIG_FILE="config.txt"

# Function to read value from config file
read_value() {
    local key=$1
    local value=$(grep "^$key=" "$CONFIG_FILE" | cut -d '=' -f 2-)
    echo "$value"
}

# Read MySQL user and password from config file
mysql_user=$(read_value "mysql_username")
mysql_password=$(read_value "mysql_password")
host=localhost

# Prompt for the new database name
read -p "Enter new MySQL database: " newDb

# Check if user already exists
userCheck=$(mysql -u root -p"$mysql_password" -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$mysql_user')")

# Check if database already exists
dbCheck=$(mysql -u root -p"$mysql_password" -sse "SELECT EXISTS(SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$newDb')")

if [ $userCheck -eq 0 ]; then
    userCommand="CREATE USER '$mysql_user'@'$host' IDENTIFIED BY '$mysql_password';GRANT USAGE ON *.* TO '$mysql_user'@'$host';"
else
    userCommand=""
    echo "User '$mysql_user' already exists, skipping user creation."
fi

if [ $dbCheck -eq 0 ]; then
    dbCommand="CREATE DATABASE \`${newDb}\`;GRANT ALL ON \`${newDb}\`.* TO '$mysql_user'@'$host';"
else
    dbCommand=""
    echo "Database '$newDb' already exists, skipping database creation."
fi

commands="$userCommand$dbCommand FLUSH PRIVILEGES;"

echo "${commands}" | /usr/bin/mysql -u root -p"$mysql_password"
