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

# Function to check if user exists for a specific host
check_user_exists() {
    local user=$1
    local host=$2
    local password=$3
    mysql -u root -p"$password" -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$user' AND host = '$host')"
}

# Function to create user for a specific host
create_user_for_host() {
    local user=$1
    local host=$2
    local password=$3
    local database=$4
    local commands=""
    
    # Check if user exists for this specific host
    local userExists=$(check_user_exists "$user" "$host" "$password")
    
    if [ $userExists -eq 0 ]; then
        echo "Creating user '$user'@'$host'..."
        commands="CREATE USER '$user'@'$host' IDENTIFIED BY '$password';"
        commands="${commands}GRANT USAGE ON *.* TO '$user'@'$host';"
        
        # Grant database permissions if database exists
        local dbExists=$(mysql -u root -p"$password" -sse "SELECT EXISTS(SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$database')")
        if [ $dbExists -eq 1 ]; then
            commands="${commands}GRANT ALL ON \`${database}\`.* TO '$user'@'$host';"
        fi
    else
        echo "User '$user'@'$host' already exists, skipping creation."
    fi
    
    echo "$commands"
}

# Read MySQL user and password from config file
MYSQL_USER=$(read_value "MYSQL_USERNAME")
MYSQL_PASSWORD=$(read_value "MYSQL_PASSWORD")
MYSQL_DATABASE=$(read_value "MYSQL_DATABASE")
MYSQL_HOST=$(read_value "MYSQL_HOST")

# Check if database already exists
dbCheck=$(mysql -u root -p"$MYSQL_PASSWORD" -sse "SELECT EXISTS(SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$MYSQL_DATABASE')")

# Create database if it doesn't exist
dbCommand=""
if [ $dbCheck -eq 0 ]; then
    dbCommand="CREATE DATABASE \`${MYSQL_DATABASE}\`;"
    echo "Database '$MYSQL_DATABASE' will be created."
else
    echo "Database '$MYSQL_DATABASE' already exists, skipping database creation."
fi

# Create user for the primary host
userCommands=$(create_user_for_host "$MYSQL_USER" "$MYSQL_HOST" "$MYSQL_PASSWORD" "$MYSQL_DATABASE")

# Store all hosts for later use
hosts=("$MYSQL_HOST")

# Ask if user wants to add more hosts
while true; do
    echo
    read -p "Do you want to grant the same permissions to '$MYSQL_USER' from another host? (y/n): " add_host
    
    if [[ $add_host =~ ^[Yy]$ ]]; then
        read -p "Enter the additional host (e.g., 'localhost', '192.168.1.%', '%' for any host): " additional_host
        additional_host=$(clean_input "$additional_host")
        
        # Check if this host was already added
        host_exists=false
        for existing_host in "${hosts[@]}"; do
            if [ "$existing_host" = "$additional_host" ]; then
                host_exists=true
                break
            fi
        done
        
        if [ "$host_exists" = false ]; then
            hosts+=("$additional_host")
            additional_commands=$(create_user_for_host "$MYSQL_USER" "$additional_host" "$MYSQL_PASSWORD" "$MYSQL_DATABASE")
            userCommands="${userCommands}${additional_commands}"
        else
            echo "Host '$additional_host' already added, skipping."
        fi
    else
        break
    fi
done

# Combine all commands
commands="${dbCommand}${userCommands}FLUSH PRIVILEGES;"

# Display summary
echo
echo "=== SUMMARY ==="
echo "Database: $MYSQL_DATABASE"
echo "User: $MYSQL_USER"
echo "Hosts that will have access:"
for host in "${hosts[@]}"; do
    echo "  - $host"
done
echo

# Confirm execution
read -p "Execute these MySQL commands? (y/n): " confirm
if [[ $confirm =~ ^[Yy]$ ]]; then
    echo "Executing MySQL commands..."
    echo "${commands}" | /usr/bin/mysql -u root -p"$MYSQL_PASSWORD"
    
    if [ $? -eq 0 ]; then
        echo "MySQL setup completed successfully!"
        echo
        echo "You can now connect to the database using:"
        for host in "${hosts[@]}"; do
            echo "  mysql -u $MYSQL_USER -p$MYSQL_PASSWORD -h $host $MYSQL_DATABASE"
        done
    else
        echo "Error executing MySQL commands. Please check the output above."
    fi
else
    echo "Operation cancelled."
fi