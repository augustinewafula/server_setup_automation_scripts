#!/bin/bash

CONFIG_FILE=".env"

# Function to clean up directory name by removing any carriage return character
clean_input() {
    local input=$1
    echo $(echo $input | tr -d '\r')
}

# Function to read value from config file or prompt user for input
read_value() {
    local key=$1
    local value=$(grep "^$key=" "$CONFIG_FILE" | cut -d '=' -f 2-)
    value=$(clean_input "$value")
    if [ -z "$value" ]; then
        read -p "Please enter the $key: " value
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
    echo "$value"
}

# Read MySQL user and password from config file
MYSQL_USER=$(read_value "MYSQL_USERNAME")
MYSQL_PASSWORD=$(read_value "MYSQL_PASSWORD")
MYSQL_DATABASE=$(read_value "MYSQL_DATABASE")
MYSQL_HOST=$(read_value "MYSQL_HOST")

# Check if user already exists
userCheck=$(mysql -u root -p"$MYSQL_PASSWORD" -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$MYSQL_USER')")

# Check if database already exists
dbCheck=$(mysql -u root -p"$MYSQL_PASSWORD" -sse "SELECT EXISTS(SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$MYSQL_DATABASE')")

if [ $userCheck -eq 0 ]; then
    userCommand="CREATE USER '$MYSQL_USER'@'$MYSQL_HOST' IDENTIFIED BY '$MYSQL_PASSWORD';GRANT USAGE ON *.* TO '$MYSQL_USER'@'$MYSQL_HOST';"
else
    userCommand=""
    echo "User '$MYSQL_USER' already exists, skipping user creation."
fi

if [ $dbCheck -eq 0 ]; then
    dbCommand="CREATE DATABASE \`${MYSQL_DATABASE}\`;GRANT ALL ON \`${MYSQL_DATABASE}\`.* TO '$MYSQL_USER'@'$MYSQL_HOST';"
else
    dbCommand=""
    echo "Database '$MYSQL_DATABASE' already exists, skipping database creation."
fi

commands="$userCommand$dbCommand FLUSH PRIVILEGES;"

echo "${commands}" | /usr/bin/mysql -u root -p"$MYSQL_PASSWORD"
