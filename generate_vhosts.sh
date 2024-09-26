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

generate_backend() {
    local BACKEND_DOMAIN_NAME=$1
    local BACKEND_SITE_PATH=$2

    echo "<VirtualHost *:80>
    ServerAdmin admin@$BACKEND_DOMAIN_NAME
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

    LogLevel debug
    ErrorLog \${APACHE_LOG_DIR}/$BACKEND_DOMAIN_NAME.error.log
    CustomLog \${APACHE_LOG_DIR}/$BACKEND_DOMAIN_NAME.access.log combined
RewriteEngine on
RewriteCond %{SERVER_NAME} =$BACKEND_DOMAIN_NAME [OR]
RewriteCond %{SERVER_NAME} =www.$BACKEND_DOMAIN_NAME
RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>"
}

generate_frontend() {
    local FRONTEND_DOMAIN_NAME=$1
    local FRONTEND_SITE_PATH=$2

    echo "<VirtualHost *:80>
    ServerAdmin admin@$FRONTEND_DOMAIN_NAME
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
    </Directory>

    LogLevel debug
    ErrorLog \${APACHE_LOG_DIR}/$FRONTEND_DOMAIN_NAME.error.log
    CustomLog \${APACHE_LOG_DIR}/$FRONTEND_DOMAIN_NAME.access.log combined
RewriteEngine on
RewriteCond %{SERVER_NAME} =$FRONTEND_DOMAIN_NAME [OR]
RewriteCond %{SERVER_NAME} =www.$FRONTEND_DOMAIN_NAME
RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>"
}

save_config() {
    local domain=$1
    local config=$2

    local filename="/etc/apache2/sites-available/$domain.conf"

    if [[ -e $filename ]]; then
        read -p "Configuration file $filename already exists. Do you want to overwrite it? [y/N] " yn
        case $yn in
            [Yy]* ) echo "$config" > "$filename"; echo "Configuration for $domain has been written to $filename.";;
            * ) echo "Skipping...";;
        esac
    else
        echo "$config" > "$filename"
        echo "Configuration for $domain has been written to $filename."
    fi
}

enable_https() {
    read -p "Do you want to enable HTTPS on the created sites? [y/N] " enable_https
    if [[ $enable_https =~ ^[Yy]$ ]]; then
        # Enable HTTPS using certbot for backend site
        if [ $choice -eq 1 ] || [ $choice -eq 3 ]; then
            sudo certbot --apache -d "$BACKEND_DOMAIN_NAME"
        fi

        # Enable HTTPS using certbot for frontend sites if they were generated
        for ((i=1; i<=2; i++)); do
            if [ "${enable_frontends[$((i-1))]}" = true ]; then
                sudo certbot --apache -d "${FRONTEND_DOMAIN_NAMES[$((i-1))]}"
            fi
        done
    else
        echo "Skipping HTTPS enablement."
    fi
}

enable_frontends=(false false)
FRONTEND_DOMAIN_NAMES=()

echo "Do you want to generate v-hosts for [1] Backend, [2] Frontend 1, [3] Frontend 2, or [4] All?"
read -p "Please enter the number corresponding to your choice: " choice

if [ $choice -lt 1 ] || [ $choice -gt 4 ]; then
    echo "Invalid choice"
    exit 1
fi

if [ $choice -eq 1 ] || [ $choice -eq 4 ]; then
    BACKEND_DOMAIN_NAME=$(read_value "BACKEND_DOMAIN_NAME")
    BACKEND_SITE_PATH=$(read_value "BACKEND_SITE_PATH")

    save_config "$BACKEND_DOMAIN_NAME" "$(generate_backend "$BACKEND_DOMAIN_NAME" "$BACKEND_SITE_PATH")"
fi

for ((i=1; i<=2; i++)); do
    if [ $choice -eq $((i+1)) ] || [ $choice -eq 4 ]; then
        enable_frontends[$((i-1))]=true

        FRONTEND_DOMAIN_NAME=$(read_value "FRONTEND${i}_DOMAIN_NAME")
        FRONTEND_SITE_PATH=$(read_value "FRONTEND${i}_SITE_PATH")
        FRONTEND_DOMAIN_NAMES+=("$FRONTEND_DOMAIN_NAME")

        save_config "$FRONTEND_DOMAIN_NAME" "$(generate_frontend "$FRONTEND_DOMAIN_NAME" "$FRONTEND_SITE_PATH")"
    fi
done

echo "V-hosts generation completed."

# Ask if the user wants to enable the sites
read -p "Do you want to enable the generated sites? [y/N] " enable_sites

if [[ $enable_sites =~ ^[Yy]$ ]]; then
    # Enable the backend site and restart Apache
    if [ $choice -eq 1 ] || [ $choice -eq 4 ]; then
        echo "Enabling $BACKEND_DOMAIN_NAME.conf..."
        sudo a2ensite "$BACKEND_DOMAIN_NAME.conf"
    fi

    # Enable the frontend sites and restart Apache if they were generated
    for ((i=1; i<=2; i++)); do
        if [ "${enable_frontends[$((i-1))]}" = true ]; then
            echo "Enabling ${FRONTEND_DOMAIN_NAMES[$((i-1))]}.conf..."
            sudo a2ensite "${FRONTEND_DOMAIN_NAMES[$((i-1))]}.conf"
        fi
    done

    sudo systemctl restart apache2

    # Ask if the user wants to enable HTTPS
    enable_https
else
    # Provide commands for the user to enable the sites and restart Apache manually
    if [ $choice -eq 1 ] || [ $choice -eq 4 ]; then
        echo "To enable $BACKEND_DOMAIN_NAME.conf, run:"
        echo "sudo a2ensite $BACKEND_DOMAIN_NAME.conf"
    fi

    # Show commands for enabling the frontend sites if they were generated
    for ((i=1; i<=2; i++)); do
        if [ "${enable_frontends[$((i-1))]}" = true ]; then
            echo "To enable ${FRONTEND_DOMAIN_NAMES[$((i-1))]}.conf, run:"
            echo "sudo a2ensite ${FRONTEND_DOMAIN_NAMES[$((i-1))]}.conf"
        fi
    done

    echo "To restart Apache, run:"
    echo "sudo systemctl restart apache2"

    # Ask if the user wants to enable HTTPS
    enable_https
fi

echo "V-hosts generation and HTTPS enablement completed."