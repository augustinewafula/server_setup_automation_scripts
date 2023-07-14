#!/bin/bash

read -p "Enter new MySQL user: " newUser
read -sp "Enter new MySQL password: " newDbPassword
echo
read -p "Enter new MySQL database: " newDb
host=localhost

# Check if user already exists
userCheck=`mysql -u root -p -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$newUser')"`

# Check if database already exists
dbCheck=`mysql -u root -p -sse "SELECT EXISTS(SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$newDb')"`

if [ $userCheck -eq 0 ]; then
    userCommand="CREATE USER '$newUser'@'$host' IDENTIFIED BY '$newDbPassword';GRANT USAGE ON *.* TO '$newUser'@'$host';"
else
    userCommand=""
    echo "User '$newUser' already exists, skipping user creation."
fi

if [ $dbCheck -eq 0 ]; then
    dbCommand="CREATE DATABASE \`${newDb}\`;GRANT ALL ON \`${newDb}\`.* TO '$newUser'@'$host';"
else
    dbCommand=""
    echo "Database '$newDb' already exists, skipping database creation."
fi

commands="$userCommand$dbCommand FLUSH PRIVILEGES;"

echo "${commands}" | /usr/bin/mysql -u root -p
