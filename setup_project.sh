#!/bin/bash

DEFAULT_DIR=$(pwd)
CONFIG_FILE="config.txt"

# Function to read value from config file or prompt user for input
read_value() {
    local key=$1
    local value=$(grep "^$key=" "$CONFIG_FILE" | cut -d '=' -f 2-)
    if [ -z "$value" ]; then
        read -p "Please enter the $key: " value
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
    echo "$value"
}

# Function to clone or pull the repository with personal access token
clone_or_pull_repo() {
    local url=$1
    local dir_name=$2
    local access_token=$3

    if [ -d "$dir_name" ]; then
        echo "Directory already exists. Performing git pull..."
        (cd "$dir_name" && GIT_ASKPASS=/bin/true git pull origin main)
    else
        GIT_ASKPASS=/bin/true git clone "$url" "$dir_name"
    fi
}

# Function to set up backend (Laravel) repository
setup_backend() {
    local backend_repo_url=$(read_value "backend_repo_url")
    local backend_dir_name=$(read_value "backend_dir_name")

    clone_or_pull_repo "$backend_repo_url" "$backend_dir_name"

    (cd "$backend_dir_name" && {
        composer install
        sudo chown -R www-data:www-data .
        sudo chmod -R 755 .
        sudo chmod -R 777 storage
        php artisan key:generate
        
        # Copy .env.example to .env
        cp .env.example .env

        # Set up the database using create_mysql_db.sh script
        cd "$DEFAULT_DIR"  # Return to the default directory
        ./create_mysql_db.sh
        cd "$backend_dir_name"  # Return to the backend directory
        
        # Update database credentials in .env file
        local db_name=$(read_value "mysql_database")
        local db_user=$(read_value "mysql_username")
        local db_password=$(read_value "mysql_password")
        sed -i "s/DB_DATABASE=.*$/DB_DATABASE=$db_name/g" .env
        sed -i "s/DB_USERNAME=.*$/DB_USERNAME=$db_user/g" .env
        sed -i "s/DB_PASSWORD=.*$/DB_PASSWORD=$db_password/g" .env
        php artisan migrate:fresh --seed
    })

    cd "$DEFAULT_DIR"  # Return to the default directory
}

# Function to set up frontend repository
setup_frontend() {
    local frontend_repo_url=$(read_value "frontend_repo_url")
    local frontend_dir_name=$(read_value "frontend_dir_name")

    clone_or_pull_repo "$frontend_repo_url" "$frontend_dir_name"

    (cd "$frontend_dir_name" && {
        yarn install
        cp .env.example .env.local

        echo "Please update the contents of .env.local with appropriate values."
        echo "After updating, run 'yarn build' to build the frontend assets."
    })

    cd "$DEFAULT_DIR"  # Return to the default directory
}

# Function to set up vhosts using generate_vhosts.sh script
setup_vhosts() {
    read -p "Do you want to set up vhosts? [y/N] " setup_vhosts
    if [[ $setup_vhosts =~ ^[Yy]$ ]]; then
        ./generate_vhosts.sh
    fi
}

# Main script starts here

# Check if the repository is for the backend (Laravel)
read -p "Do you want to set up the backend? [y/N] " is_backend

if [[ $is_backend =~ ^[Yy]$ ]]; then
    backend_repo_url=$(read_value "backend_repo_url")
    setup_backend
fi

# Set up the frontend if needed
read -p "Do you want to set up the frontend? [y/N] " setup_frontend

if [[ $setup_frontend =~ ^[Yy]$ ]]; then
    backend_dir_name=$(read_value "backend_dir_name")
    setup_frontend
fi

echo "Setup complete!"

setup_vhosts
