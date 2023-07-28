#!/bin/bash

CONFIG_FILE="config.txt"

# Function to read value from config file
read_value() {
    local key=$1
    local value=$(grep "^$key=" "$CONFIG_FILE" | cut -d '=' -f 2-)
    if [ -z "$value" ]; then
        read -p "Please enter the $key: " value
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
    echo "$value"
}

# Read MySQL user and password from config file
mysql_user=$(read_value "mysql_username")
mysql_password=$(read_value "mysql_password")
mysql_database=$(read_value "mysql_database")
mysql_host=$(read_value "mysql_host")

# Check if user already exists
userCheck=$(mysql -u root -p"$mysql_password" -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$mysql_user')")

# Check if database already exists
dbCheck=$(mysql -u root -p"$mysql_password" -sse "SELECT EXISTS(SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$mysql_database')")

if [ $userCheck -eq 0 ]; then
    userCommand="CREATE USER '$mysql_user'@'$mysql_host' IDENTIFIED BY '$mysql_password';GRANT USAGE ON *.* TO '$mysql_user'@'$mysql_host';"
else
    userCommand=""
    echo "User '$mysql_user' already exists, skipping user creation."
fi

if [ $dbCheck -eq 0 ]; then
    dbCommand="CREATE DATABASE \`${mysql_database}\`;GRANT ALL ON \`${mysql_database}\`.* TO '$mysql_user'@'$mysql_host';"
else
    dbCommand=""
    echo "Database '$mysql_database' already exists, skipping database creation."
fi

commands="$userCommand$dbCommand FLUSH PRIVILEGES;"

echo "${commands}" | /usr/bin/mysql -u root -p"$mysql_password"
