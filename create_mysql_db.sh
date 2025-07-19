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

# Function to test MySQL connection
test_mysql_connection() {
    local password=$1
    mysql -u root -p"$password" -e "SELECT 1;" >/dev/null 2>&1
    return $?
}

# Function to check if user exists for a specific host
check_user_exists() {
    local user=$1
    local host=$2
    local password=$3
    mysql -u root -p"$password" -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$user' AND host = '$host')" 2>/dev/null
}

# Function to check if user has permissions on database
check_user_database_permissions() {
    local user=$1
    local host=$2
    local database=$3
    local password=$4
    mysql -u root -p"$password" -sse "SELECT COUNT(*) FROM information_schema.schema_privileges WHERE grantee = \"'$user'@'$host'\" AND table_schema = '$database'" 2>/dev/null
}

# Function to check if database exists
check_database_exists() {
    local database=$1
    local password=$2
    mysql -u root -p"$password" -sse "SELECT EXISTS(SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$database')" 2>/dev/null
}

# Function to create or update user for a specific host
create_or_update_user_for_host() {
    local user=$1
    local host=$2
    local user_password=$3
    local root_password=$4
    local database=$5
    local commands=""
    local action_taken=false
    
    # Check if user exists for this specific host
    local userExists=$(check_user_exists "$user" "$host" "$root_password")
    
    if [ $userExists -eq 0 ]; then
        echo "Creating user '$user'@'$host'..." >&2
        commands="CREATE USER '$user'@'$host' IDENTIFIED BY '$user_password';"
        action_taken=true
    else
        echo "User '$user'@'$host' already exists. Updating password..." >&2
        commands="ALTER USER '$user'@'$host' IDENTIFIED BY '$user_password';"
        action_taken=true
    fi
    
    # Always ensure basic usage grant exists
    commands="${commands}GRANT USAGE ON *.* TO '$user'@'$host';"
    
    # Check and grant database permissions if database exists or will be created
    local dbExists=$(check_database_exists "$database" "$root_password")
    if [ $dbExists -eq 1 ] || [ "$CREATE_DATABASE" = true ]; then
        local hasPermissions=$(check_user_database_permissions "$user" "$host" "$database" "$root_password")
        if [ $hasPermissions -eq 0 ]; then
            echo "Granting database permissions to '$user'@'$host' for database '$database'..." >&2
            commands="${commands}GRANT ALL PRIVILEGES ON \`${database}\`.* TO '$user'@'$host';"
            action_taken=true
        else
            echo "Re-granting database permissions to '$user'@'$host' for database '$database' (ensuring consistency)..." >&2
            commands="${commands}GRANT ALL PRIVILEGES ON \`${database}\`.* TO '$user'@'$host';"
        fi
    fi
    
    if [ "$action_taken" = true ]; then
        echo "$commands"
    else
        echo ""
    fi
}

# Function to validate input parameters
validate_inputs() {
    if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$MYSQL_DATABASE" ] || [ -z "$MYSQL_HOST" ]; then
        echo "Error: All required parameters must be provided (MYSQL_USERNAME, MYSQL_PASSWORD, MYSQL_DATABASE, MYSQL_HOST)"
        exit 1
    fi
    
    # Validate MySQL connection
    if ! test_mysql_connection "$ROOT_PASSWORD"; then
        echo "Error: Cannot connect to MySQL with root password. Please check your root password."
        exit 1
    fi
}

# Function to display summary
display_summary() {
    local hosts_array=("$@")
    echo
    echo "=== SUMMARY ==="
    echo "Database: $MYSQL_DATABASE"
    echo "User: $MYSQL_USER"
    echo "User Password: $MYSQL_PASSWORD"
    echo "Hosts that will have access:"
    for host in "${hosts_array[@]}"; do
        echo "  - $host"
    done
    echo
}

# Function to display connection examples
display_connection_examples() {
    local hosts_array=("$@")
    echo "You can now connect to the database using:"
    for host in "${hosts_array[@]}"; do
        if [ "$host" = "localhost" ] || [ "$host" = "127.0.0.1" ]; then
            echo "  mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE"
            echo "  mysql -u $MYSQL_USER -p$MYSQL_PASSWORD -h $host $MYSQL_DATABASE"
        else
            echo "  mysql -u $MYSQL_USER -p$MYSQL_PASSWORD -h $host $MYSQL_DATABASE"
        fi
    done
}

# Function to ensure localhost access when using 127.0.0.1
ensure_localhost_access() {
    local user=$1
    local user_password=$2
    local root_password=$3
    local database=$4
    local commands=""
    
    # If primary host is 127.0.0.1, also create localhost user for compatibility
    if [ "$MYSQL_HOST" = "127.0.0.1" ]; then
        echo "Also ensuring 'localhost' access for compatibility..." >&2
        local localhost_commands=$(create_or_update_user_for_host "$user" "localhost" "$user_password" "$root_password" "$database")
        commands="${commands}${localhost_commands}"
        hosts+=("localhost")
    fi
    
    echo "$commands"
}

# Main script execution starts here
echo "=== MySQL Database and User Setup Script ==="
echo

# Read configuration values
MYSQL_USER=$(read_value "MYSQL_USERNAME")
MYSQL_PASSWORD=$(read_value "MYSQL_PASSWORD")
MYSQL_DATABASE=$(read_value "MYSQL_DATABASE")
MYSQL_HOST=$(read_value "MYSQL_HOST")

# Read MySQL root password from config file or prompt
ROOT_PASSWORD=$(read_value "MYSQL_PASSWORD")

# Validate all inputs
validate_inputs

# Check if database already exists
CREATE_DATABASE=false
dbCheck=$(check_database_exists "$MYSQL_DATABASE" "$ROOT_PASSWORD")

# Prepare database command if needed
dbCommand=""
if [ $dbCheck -eq 0 ]; then
    dbCommand="CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    CREATE_DATABASE=true
    echo "Database '$MYSQL_DATABASE' will be created."
else
    echo "Database '$MYSQL_DATABASE' already exists."
fi

# Create or update user for the primary host
echo "Processing primary host: $MYSQL_HOST"
userCommands=$(create_or_update_user_for_host "$MYSQL_USER" "$MYSQL_HOST" "$MYSQL_PASSWORD" "$ROOT_PASSWORD" "$MYSQL_DATABASE")

# Store all hosts for later use
hosts=("$MYSQL_HOST")

# Ensure localhost access if using 127.0.0.1
localhostCommands=$(ensure_localhost_access "$MYSQL_USER" "$MYSQL_PASSWORD" "$ROOT_PASSWORD" "$MYSQL_DATABASE")
userCommands="${userCommands}${localhostCommands}"

# Ask if user wants to add more hosts
while true; do
    echo
    read -p "Do you want to grant the same permissions to '$MYSQL_USER' from another host? (y/n): " add_host
    
    if [[ $add_host =~ ^[Yy]$ ]]; then
        read -p "Enter the additional host (e.g., 'localhost', '192.168.1.%', '%' for any host): " additional_host
        additional_host=$(clean_input "$additional_host")
        
        # Validate host input
        if [ -z "$additional_host" ]; then
            echo "Error: Host cannot be empty."
            continue
        fi
        
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
            echo "Processing additional host: $additional_host"
            additional_commands=$(create_or_update_user_for_host "$MYSQL_USER" "$additional_host" "$MYSQL_PASSWORD" "$ROOT_PASSWORD" "$MYSQL_DATABASE")
            userCommands="${userCommands}${additional_commands}"
        else
            echo "Host '$additional_host' already added, skipping."
        fi
    else
        break
    fi
done

# Combine all commands
commands="${dbCommand}${userCommands}"

# Always add FLUSH PRIVILEGES to ensure changes take effect
if [ -n "$commands" ]; then
    commands="${commands}FLUSH PRIVILEGES;"
fi

# Display summary
display_summary "${hosts[@]}"

# Execute commands if there are any
if [ -n "$commands" ]; then
    # Confirm execution
    read -p "Execute these MySQL commands? (y/n): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo "Executing MySQL commands..."
        
        # Execute commands and capture both stdout and stderr
        if echo "${commands}" | mysql -u root -p"$ROOT_PASSWORD" 2>&1; then
            echo "MySQL setup completed successfully!"
            echo
            display_connection_examples "${hosts[@]}"
        else
            echo "Error executing MySQL commands. Please check the output above."
            exit 1
        fi
    else
        echo "Operation cancelled."
        exit 0
    fi
else
    echo "No MySQL commands to execute."
    echo
    display_connection_examples "${hosts[@]}"
fi

echo
echo "Setup completed. Configuration saved to $CONFIG_FILE"