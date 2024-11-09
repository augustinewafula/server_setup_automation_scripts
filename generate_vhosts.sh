#!/bin/bash

set -e  # Exit on error
set -u  # Exit on undefined variable

CONFIG_FILE=".env"
APACHE_AVAILABLE_SITES="/etc/apache2/sites-available"
APACHE_LOG_DIR="\${APACHE_LOG_DIR}"

# Check if script is run with sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run this script with sudo"
        exit 1
    fi
}

# Enhanced check_dependencies function
check_dependencies() {
    local dependencies=("apache2" "certbot")
    local apache_modules=("headers" "rewrite" "ssl")
    local missing_deps=()
    local missing_modules=()

    # Check software dependencies
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    # Check Apache modules
    for module in "${apache_modules[@]}"; do
        if ! a2query -m "$module" &> /dev/null; then
            missing_modules+=("$module")
        fi
    done

    # Install missing dependencies if any
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Missing required dependencies: ${missing_deps[*]}"
        read -p "Would you like to install them now? [y/N] " install_deps
        if [[ $install_deps =~ ^[Yy]$ ]]; then
            apt-get update
            apt-get install -y "${missing_deps[@]}"
        else
            echo "Please install the required dependencies and try again."
            exit 1
        fi
    fi

    # Enable missing Apache modules if any
    if [ ${#missing_modules[@]} -ne 0 ]; then
        echo "Missing required Apache modules: ${missing_modules[*]}"
        read -p "Would you like to enable them now? [y/N] " enable_modules
        if [[ $enable_modules =~ ^[Yy]$ ]]; then
            for module in "${missing_modules[@]}"; do
                echo "Enabling Apache module: $module"
                sudo a2enmod "$module"
            done
            echo "Apache modules enabled. Restarting Apache..."
            sudo systemctl restart apache2
        else
            echo "Please enable the required Apache modules and try again."
            echo "You can enable them manually with these commands:"
            for module in "${missing_modules[@]}"; do
                echo "sudo a2enmod $module"
            done
            echo "sudo systemctl restart apache2"
            exit 1
        fi
    fi
}

# Function to create backup of existing configuration
backup_config() {
    local filename=$1
    if [[ -e $filename ]]; then
        local backup_file="${filename}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$filename" "$backup_file"
        echo "Backup created: $backup_file"
    fi
}

# Function to clean up directory name by removing any carriage return character
clean_input() {
    local input=$1
    echo "${input}" | tr -d '\r'
}

# Function to validate domain name format
validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo "Invalid domain name format: $domain"
        return 1
    fi
    return 0
}

# Function to validate path
validate_path() {
    local path=$1
    if [[ ! -d "$path" ]]; then
        read -p "Directory $path does not exist. Create it? [y/N] " create_dir
        if [[ $create_dir =~ ^[Yy]$ ]]; then
            mkdir -p "$path"
        else
            return 1
        fi
    fi
    return 0
}

# Function to read value from config file or prompt user for input with validation
read_value() {
    local key=$1
    local prompt=$2
    local validation_function=$3
    local value

    # Try to read from config file first
    if [[ -f "$CONFIG_FILE" ]]; then
        value=$(grep "^$key=" "$CONFIG_FILE" 2>/dev/null | cut -d '=' -f 2-)
        value=$(clean_input "$value")
    fi

    # If value is empty or invalid, prompt user
    while [[ -z "${value:-}" ]] || ! $validation_function "$value"; do
        read -p "$prompt: " value
        if [[ -n "$value" ]] && $validation_function "$value"; then
            echo "$key=$value" >> "$CONFIG_FILE"
            break
        else
            echo "Invalid input. Please try again."
        fi
    done

    echo "$value"
}

generate_backend() {
    local BACKEND_DOMAIN_NAME=$1
    local BACKEND_SITE_PATH=$2

    cat << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$BACKEND_DOMAIN_NAME
    ServerName $BACKEND_DOMAIN_NAME
    ServerAlias www.$BACKEND_DOMAIN_NAME
    DocumentRoot $BACKEND_SITE_PATH

    <Directory $BACKEND_SITE_PATH/>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
        Require all granted
    </Directory>

    # Enable CORS headers
    Header always set Access-Control-Allow-Origin "*"
    Header always set Access-Control-Allow-Methods "POST, GET, OPTIONS, DELETE, PUT"
    Header always set Access-Control-Allow-Headers "Content-Type, Authorization"

    # Security headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    LogLevel warn
    ErrorLog ${APACHE_LOG_DIR}/$BACKEND_DOMAIN_NAME.error.log
    CustomLog ${APACHE_LOG_DIR}/$BACKEND_DOMAIN_NAME.access.log combined

    RewriteEngine on
    RewriteCond %{SERVER_NAME} =$BACKEND_DOMAIN_NAME [OR]
    RewriteCond %{SERVER_NAME} =www.$BACKEND_DOMAIN_NAME
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
EOF
}

generate_frontend() {
    local FRONTEND_DOMAIN_NAME=$1
    local FRONTEND_SITE_PATH=$2

    cat << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$FRONTEND_DOMAIN_NAME
    ServerName $FRONTEND_DOMAIN_NAME
    ServerAlias www.$FRONTEND_DOMAIN_NAME
    DocumentRoot $FRONTEND_SITE_PATH
    DirectoryIndex index.html

    <Directory $FRONTEND_SITE_PATH/>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
        Require all granted

        # Handle Single Page Application routing
        RewriteEngine On
        RewriteBase /
        RewriteRule ^index\.html$ - [L]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . /index.html [L]
    </Directory>

    # Cache control for static assets
    <FilesMatch "\.(ico|pdf|jpg|jpeg|png|gif|js|css|svg|woff2?)$">
        Header set Cache-Control "max-age=31536000, public"
    </FilesMatch>

    # Security headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"

    LogLevel warn
    ErrorLog ${APACHE_LOG_DIR}/$FRONTEND_DOMAIN_NAME.error.log
    CustomLog ${APACHE_LOG_DIR}/$FRONTEND_DOMAIN_NAME.access.log combined

    RewriteEngine on
    RewriteCond %{SERVER_NAME} =$FRONTEND_DOMAIN_NAME [OR]
    RewriteCond %{SERVER_NAME} =www.$FRONTEND_DOMAIN_NAME
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
EOF
}

save_config() {
    local domain=$1
    local config=$2
    local filename="$APACHE_AVAILABLE_SITES/$domain.conf"

    if [[ -e $filename ]]; then
        backup_config "$filename"
        read -p "Configuration file $filename already exists. Do you want to overwrite it? [y/N] " yn
        case $yn in
            [Yy]* ) 
                echo "$config" > "$filename"
                echo "Configuration for $domain has been updated."
                ;;
            * ) 
                echo "Skipping..."
                return 1
                ;;
        esac
    else
        echo "$config" > "$filename"
        echo "Configuration for $domain has been created."
    fi
    return 0
}

enable_https() {
    local -a domains=()
    
    if [[ " ${selected_choices[@]} " =~ " 1 " ]]; then
        domains+=("$BACKEND_DOMAIN_NAME")
    fi

    for ((i=1; i<=2; i++)); do
        if [ "${enable_frontends[$((i-1))]}" = true ]; then
            domains+=("${FRONTEND_DOMAIN_NAMES[$((i-1))]}")
        fi
    done

    if [ ${#domains[@]} -eq 0 ]; then
        echo "No domains to configure HTTPS for."
        return
    fi

    read -p "Do you want to enable HTTPS for the following domains? [${domains[*]}] [y/N] " enable_https
    if [[ $enable_https =~ ^[Yy]$ ]]; then
        for domain in "${domains[@]}"; do
            echo "Enabling HTTPS for $domain..."
            if ! sudo certbot --apache -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email "webmaster@$domain"; then
                echo "Failed to enable HTTPS for $domain. Please check the certbot logs."
            fi
        done
    else
        echo "Skipping HTTPS enablement."
    fi
}

# Main script execution starts here
main() {
    check_sudo
    check_dependencies

    # Create config file if it doesn't exist
    touch "$CONFIG_FILE"

    enable_frontends=(false false)
    FRONTEND_DOMAIN_NAMES=()

    # Show menu
    echo "Which v-hosts do you want to generate?"
    echo "[1] Backend"
    echo "[2] Frontend 1"
    echo "[3] Frontend 2"
    echo "[4] All"
    echo "You can select multiple options by separating them with commas (e.g., '1,2' or '1,3')"
    read -p "Please enter your choice(s): " choices

    # Convert choice string to array and remove whitespace
    IFS=',' read -ra selected_choices <<< "$choices"
    selected_choices=("${selected_choices[@]// /}")

    # Validate choices
    valid_choices=true
    for choice in "${selected_choices[@]}"; do
        if ! [[ "$choice" =~ ^[1-4]$ ]]; then
            echo "Invalid choice: $choice"
            valid_choices=false
            break
        fi
    done

    if [ "$valid_choices" = false ]; then
        echo "Please enter valid numbers between 1 and 4"
        exit 1
    fi

    # Check if "4" (All) is selected along with other options
    if [[ " ${selected_choices[@]} " =~ " 4 " ]] && [ ${#selected_choices[@]} -gt 1 ]; then
        echo "Warning: Option 4 (All) was selected along with other options. Will generate all v-hosts."
        selected_choices=("4")
    fi

    # Generate backend configuration if selected
    if [[ " ${selected_choices[@]} " =~ " 1 " ]] || [[ " ${selected_choices[@]} " =~ " 4 " ]]; then
        BACKEND_DOMAIN_NAME=$(read_value "BACKEND_DOMAIN_NAME" "Enter the backend domain name" validate_domain)
        BACKEND_SITE_PATH=$(read_value "BACKEND_SITE_PATH" "Enter the backend site path" validate_path)

        save_config "$BACKEND_DOMAIN_NAME" "$(generate_backend "$BACKEND_DOMAIN_NAME" "$BACKEND_SITE_PATH")"
    fi

    # Generate frontend configurations if selected
    for ((i=1; i<=2; i++)); do
        if [[ " ${selected_choices[@]} " =~ " $((i+1)) " ]] || [[ " ${selected_choices[@]} " =~ " 4 " ]]; then
            enable_frontends[$((i-1))]=true

            FRONTEND_DOMAIN_NAME=$(read_value "FRONTEND${i}_DOMAIN_NAME" "Enter frontend ${i} domain name" validate_domain)
            FRONTEND_SITE_PATH=$(read_value "FRONTEND${i}_SITE_PATH" "Enter frontend ${i} site path" validate_path)
            FRONTEND_DOMAIN_NAMES+=("$FRONTEND_DOMAIN_NAME")

            save_config "$FRONTEND_DOMAIN_NAME" "$(generate_frontend "$FRONTEND_DOMAIN_NAME" "$FRONTEND_SITE_PATH")"
        fi
    done

    echo "V-hosts generation completed."

    # Enable sites
    local sites_enabled=false
    read -p "Do you want to enable the generated sites? [y/N] " enable_sites
    if [[ $enable_sites =~ ^[Yy]$ ]]; then
        if [[ " ${selected_choices[@]} " =~ " 1 " ]] || [[ " ${selected_choices[@]} " =~ " 4 " ]]; then
            echo "Enabling $BACKEND_DOMAIN_NAME.conf..."
            sudo a2ensite "$BACKEND_DOMAIN_NAME.conf"
            sites_enabled=true
        fi

        for ((i=1; i<=2; i++)); do
            if [ "${enable_frontends[$((i-1))]}" = true ]; then
                echo "Enabling ${FRONTEND_DOMAIN_NAMES[$((i-1))]}.conf..."
                sudo a2ensite "${FRONTEND_DOMAIN_NAMES[$((i-1))]}.conf"
                sites_enabled=true
            fi
        done

        if [ "$sites_enabled" = true ]; then
            echo "Restarting Apache..."
            if ! sudo apache2ctl configtest; then
                echo "Apache configuration test failed. Please check your configurations."
                exit 1
            fi
            sudo systemctl restart apache2
        fi

        # Configure HTTPS
        enable_https
    else
        # Show manual commands
        echo "To enable the sites manually, run the following commands:"
        if [[ " ${selected_choices[@]} " =~ " 1 " ]] || [[ " ${selected_choices[@]} " =~ " 4 " ]]; then
            echo "sudo a2ensite $BACKEND_DOMAIN_NAME.conf"
        fi

        for ((i=1; i<=2; i++)); do
            if [ "${enable_frontends[$((i-1))]}" = true ]; then
                echo "sudo a2ensite ${FRONTEND_DOMAIN_NAMES[$((i-1))]}.conf"
            fi
        done

        echo "sudo apache2ctl configtest"
        echo "sudo systemctl restart apache2"

        # Offer HTTPS configuration
        enable_https
    fi

    echo "V-hosts generation and HTTPS enablement completed."
}

# Execute main function
main