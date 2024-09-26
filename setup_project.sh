#!/bin/bash

DEFAULT_DIR=$(pwd)
CONFIG_FILE=".env"

# Function to clean up directory name by removing any carriage return character
clean_input() {
    local input=$1
    echo $(echo "$input" | tr -d '\r')
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
    local access_token=$(read_value "GITHUB_ACCESS_TOKEN")

    if [ -d "$dir_name" ]; then
        run_task_with_output "Git pull in $dir_name"
        (cd "$dir_name" && GIT_ASKPASS=/bin/true git pull origin main)
        task_completed "Git pull in $dir_name"
    else
        # Modify the clone command to include the access token in the URL
        run_task_with_output "Git clone $url into $dir_name"
        GIT_ASKPASS=/bin/true git clone "${url/github.com/$access_token@github.com}" "$dir_name"
        task_completed "Git clone $url into $dir_name"
    fi
}

# Function to set up backend (Laravel) repository
setup_backend() {
    local BACKEND_REPO_URL=$(read_value "BACKEND_REPO_URL")
    local BACKEND_DIR_NAME=$(read_value "BACKEND_DIR_NAME")
    local APP_NAME=$(read_value "APP_NAME")

    clone_or_pull_repo "$BACKEND_REPO_URL" "$BACKEND_DIR_NAME"

    (cd "$BACKEND_DIR_NAME" && {
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

        # Set APP_NAME, APP_ENV to "production" and APP_DEBUG to "false" in .env
        sed -i "s/^APP_NAME=.*$/APP_NAME=$APP_NAME/g" .env
        sed -i "s/^APP_ENV=.*$/APP_ENV=production/g" .env
        sed -i "s/^APP_DEBUG=.*$/APP_DEBUG=false/g" .env

        # Set up the database using create_mysql_db.sh script
        cd "$DEFAULT_DIR"  # Return to the default directory
        run_task_with_output "Setting up the database"
        ./create_mysql_db.sh
        task_completed "Setting up the database"

        # Update database credentials in .env file
        run_task_with_output "Updating database credentials on .env file"
        local db_name=$(read_value "MYSQL_DATABASE")
        local db_user=$(read_value "MYSQL_USERNAME")
        local db_password=$(read_value "MYSQL_PASSWORD")
        cd "$BACKEND_DIR_NAME"
        sed -i "s/^DB_DATABASE=.*$/DB_DATABASE=$db_name/g" .env
        sed -i "s/^DB_USERNAME=.*$/DB_USERNAME=$db_user/g" .env
        sed -i "s/^DB_PASSWORD=.*$/DB_PASSWORD=\"$db_password\"/g" .env
        task_completed "Updating database credentials on .env file"

        # Read the comma-separated variable names from the ADDITIONAL_ENV_VARS key in .env
        run_task_with_output "Setting additional environment variables in .env file"
        cd "$DEFAULT_DIR"  # Return to the default directory
        env_vars_key=$(read_value "ADDITIONAL_ENV_VARS")

        # Convert the comma-separated list into an array
        IFS=',' read -r -a additional_env_vars <<< "$env_vars_key"

        # Loop through each variable name, read its value using read_value(), and update it in the .env file
        for var_name in "${additional_env_vars[@]}"; do
            var_value=$(read_value "$var_name")
            
            cd "$BACKEND_DIR_NAME"

            # Ensure that the variable value is properly quoted to handle special characters
            # Also handle the case where the variable might not exist in the .env file yet
            if grep -q "^$var_name=" .env; then
                escaped_value=$(printf '%s' "$var_value" | sed 's/[&/\]/\\&/g')
                sed -i "s/^$var_name=.*\$/$var_name=$escaped_value/" .env
                echo "Updated: $var_name=$var_value"
            else
                echo "$var_name=$var_value" >> .env
                echo "Added: $var_name=$var_value"
            fi
            cd "$DEFAULT_DIR" 
        done
        task_completed "Setting additional environment variables in .env file"

        # Run database migrations
        run_task_with_output "Running database migrations in backend"0
        cd "$BACKEND_DIR_NAME"
        php artisan migrate:fresh --seed
        task_completed "Running database migrations in backend"
    })

    cd "$DEFAULT_DIR"  # Return to the default directory
}

# Function to set up frontend repository
setup_frontend() {
    local frontend_number=$1
    local FRONTEND_REPO_URL=$(read_value "FRONTEND${frontend_number}_REPO_URL")
    local FRONTEND_DIR_NAME=$(read_value "FRONTEND${frontend_number}_DIR_NAME")
    local BACKEND_DOMAIN_NAME=$(read_value "BACKEND_DOMAIN_NAME")
    local APP_NAME=$(read_value "APP_NAME")

    clone_or_pull_repo "$FRONTEND_REPO_URL" "$FRONTEND_DIR_NAME"

    (cd "$FRONTEND_DIR_NAME" && {
        # Check if Yarn is installed
        if ! command -v yarn &> /dev/null; then
            echo "Yarn not found. Please install Yarn before proceeding."
            exit 1
        fi

        # Run yarn install to install dependencies
        run_task_with_output "Running yarn install in frontend"
        yarn install || { echo "Error: Yarn install failed."; exit 1; }

        # Copy environment example file and configure it
        cp .env.example .env.local

        # Update .env.local with appropriate values
        sed -i "s/^VUE_APP_API_BASE_URL=.*$/VUE_APP_API_BASE_URL=https:\/\/$BACKEND_DOMAIN_NAME\/api\/v1\//g" .env.local
        sed -i "s/^VUE_APP_TITLE=.*$/VUE_APP_TITLE=$APP_NAME/g" .env.local

        echo "Updated .env.local with backend and app information."

        # Check if deploy.sh script exists, if so, use it for deployment
        if [[ -f "./deploy.sh" ]]; then
            echo "Found deploy.sh in $frontend_dir_name. Using it for deployment..."
            chmod +x ./deploy.sh
            ./deploy.sh || { echo "Error: deploy.sh script failed."; exit 1; }
        else
            # If deploy.sh is not present, run the default yarn build process
            run_task_with_output "Running yarn build in frontend"
            yarn build || { echo "Error: Yarn build failed."; exit 1; }
            task_completed "Running yarn build in frontend"
        fi
    })

    # Return to the default directory
    cd "$DEFAULT_DIR"
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
is_backend=$(clean_input "$is_backend")

if [[ $is_backend =~ ^[Yy]$ ]]; then
    BACKEND_REPO_URL=$(read_value "BACKEND_REPO_URL")
    run_task_with_output "Setting up backend"
    setup_backend
    task_completed "Setting up backend"
fi

# Set up the frontends if needed
setup_frontends=()
for i in 1 2; do
    read -p "Do you want to set up frontend $i? [y/N] " response
    setup_frontends+=("$response")
done

for i in 1 2; do
    if [[ "${setup_frontends[$((i-1))]}" =~ ^[Yy]$ ]]; then
        run_task_with_output "Setting up frontend $i"
        setup_frontend $i
        task_completed "Setting up frontend $i"
    fi
done

echo "Setup complete!"

setup_vhosts
