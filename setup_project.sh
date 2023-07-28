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

# Function to output a message before running a task
run_task_with_output() {
    local task_name=$1
    echo ">>> About to run: $task_name"
}

# Function to output a message after completing a task
task_completed() {
    local task_name=$1
    echo ">>> Completed: $task_name"
}

# Function to clone or pull the repository with personal access token
clone_or_pull_repo() {
    local url=$1
    local dir_name=$2
    local access_token=$3

    if [ -d "$dir_name" ]; then
        run_task_with_output "Git pull in $dir_name"
        (cd "$dir_name" && GIT_ASKPASS=/bin/true git pull origin main)
        task_completed "Git pull in $dir_name"
    else
        run_task_with_output "Git clone $url into $dir_name"
        GIT_ASKPASS=/bin/true git clone "$url" "$dir_name"
        task_completed "Git clone $url into $dir_name"
    fi
}

# Function to set up backend (Laravel) repository
setup_backend() {
    local backend_repo_url=$(read_value "backend_repo_url")
    local backend_dir_name=$(read_value "backend_dir_name")

    clone_or_pull_repo "$backend_repo_url" "$backend_dir_name"

    (cd "$backend_dir_name" && {
        run_task_with_output "Running composer install in backend"
        composer install
        task_completed "Running composer install in backend"

        run_task_with_output "Setting proper ownership and permissions in backend"
        sudo chown -R www-data:www-data .
        sudo chmod -R 755 .
        sudo chmod -R 777 storage
        task_completed "Setting proper ownership and permissions in backend"

        # Copy .env.example to .env
        cp .env.example .env

        # Generate Laravel application key
        run_task_with_output "Generating Laravel application key in backend"
        php artisan key:generate
        task_completed "Generating Laravel application key in backend"

        # Set APP_ENV to "production" and APP_DEBUG to "false" in .env
        sed -i "s/^APP_ENV=.*$/APP_ENV=production/g" .env
        sed -i "s/^APP_DEBUG=.*$/APP_DEBUG=false/g" .env

        # Set up the database using create_mysql_db.sh script
        cd "$DEFAULT_DIR"  # Return to the default directory
        run_task_with_output "Setting up the database"
        ./create_mysql_db.sh
        task_completed "Setting up the database"

        # Update database credentials in .env file
        run_task_with_output "Updating database credentials on .env file"
        local db_name=$(read_value "mysql_database")
        local db_user=$(read_value "mysql_username")
        local db_password=$(read_value "mysql_password")
        cd "$backend_dir_name"
        sed -i "s/DB_DATABASE=.*$/DB_DATABASE=$db_name/g" .env
        sed -i "s/DB_USERNAME=.*$/DB_USERNAME=$db_user/g" .env
        sed -i "s/DB_PASSWORD=.*$/DB_PASSWORD=\"$db_password\"/g" .env
        task_completed "Updating database credentials on .env file"

        # Run database migrations
        run_task_with_output "Running database migrations in backend"
        php artisan migrate:fresh --seed
        task_completed "Running database migrations in backend"
    })

    cd "$DEFAULT_DIR"  # Return to the default directory
}

# Function to set up frontend repository
setup_frontend() {
    local frontend_repo_url=$(read_value "frontend_repo_url")
    local frontend_dir_name=$(read_value "frontend_dir_name")

    clone_or_pull_repo "$frontend_repo_url" "$frontend_dir_name"

    (cd "$frontend_dir_name" && {
        run_task_with_output "Running yarn install in frontend"
        yarn install
        cp .env.example .env.local
        
        echo "Please update the contents of .env.local with appropriate values."
        echo "After updating, run 'yarn build' to build the frontend assets."
    })

    cd "$DEFAULT_DIR"  # Return to the default directory
}

# Function to set up vhosts using generate_vhosts.sh script
setup_vhosts() {
    cd "$DEFAULT_DIR"  # Return to the default directory
    read -p "Do you want to set up vhosts? [y/N] " setup_vhosts
    if [[ $setup_vhosts =~ ^[Yy]$ ]]; then
        run_task_with_output "Setting up vhosts"
        ./generate_vhosts.sh
        task_completed "Setting up vhosts"
    fi
}

# Main script starts here

# Check if the repository is for the backend (Laravel)
read -p "Do you want to set up the backend? [y/N] " is_backend

if [[ $is_backend =~ ^[Yy]$ ]]; then
    backend_repo_url=$(read_value "backend_repo_url")
    run_task_with_output "Setting up backend"
    setup_backend
    task_completed "Setting up backend"
fi

# Set up the frontend if needed
read -p "Do you want to set up the frontend? [y/N] " setup_frontend

if [[ $setup_frontend =~ ^[Yy]$ ]]; then
    backend_dir_name=$(read_value "backend_dir_name")
    run_task_with_output "Setting up frontend"
    setup_frontend
    task_completed "Setting up frontend"
fi

echo "Setup complete!"

setup_vhosts
