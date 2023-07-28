#!/bin/bash

CONFIG_FILE="config.txt"

# Function to read value from config file or prompt user for input
read_value() {
    local key=$1
    local value=$(grep "^$key=" "$CONFIG_FILE" | cut -d '=' -f 2-)
    if [ -z "$value" ]; then
        read -p "Please enter the $key: " value
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
}

generate_backend() {
    echo "<VirtualHost *:80>
    ServerAdmin admin@$backend_domain_name
    ServerName $backend_domain_name
    ServerAlias www.$backend_domain_name
    DocumentRoot $backend_site_path

    <Directory $backend_site_path/>
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Order allow,deny
            allow from all
            Require all granted
    </Directory>

    LogLevel debug
    ErrorLog \${APACHE_LOG_DIR}/$backend_domain_name.error.log
    CustomLog \${APACHE_LOG_DIR}/$backend_domain_name.access.log combined
RewriteEngine on
RewriteCond %{SERVER_NAME} =$backend_domain_name [OR]
RewriteCond %{SERVER_NAME} =www.$backend_domain_name
RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>"
}

generate_frontend() {
    echo "<VirtualHost *:80>
    ServerAdmin admin@$frontend_domain_name
    ServerName $frontend_domain_name
    ServerAlias www.$frontend_domain_name
    DocumentRoot $frontend_site_path
    DirectoryIndex index.html

    <Directory $frontend_site_path/>
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Order allow,deny
            allow from all
            Require all granted
    </Directory>

    LogLevel debug
    ErrorLog \${APACHE_LOG_DIR}/$frontend_domain_name.error.log
    CustomLog \${APACHE_LOG_DIR}/$frontend_domain_name.access.log combined
RewriteEngine on
RewriteCond %{SERVER_NAME} =$frontend_domain_name [OR]
RewriteCond %{SERVER_NAME} =www.$frontend_domain_name
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

enable_frontend=false

echo "Do you want to generate v-hosts for [1] Backend, [2] Frontend or [3] Both?"
read choice

if [ $choice -lt 1 ] || [ $choice -gt 3 ]; then
    echo "Invalid choice"
    exit 1
fi

if [ $choice -eq 1 ] || [ $choice -eq 3 ]; then
    read_value "backend_domain_name"
    read_value "backend_site_path"

    save_config "$backend_domain_name" "$(generate_backend)"
fi

if [ $choice -eq 2 ] || [ $choice -eq 3 ]; then
    enable_frontend=true

    read_value "frontend_domain_name"
    read_value "frontend_site_path"

    save_config "$frontend_domain_name" "$(generate_frontend)"
fi

echo "V-hosts generation completed."

# Ask if the user wants to enable the sites
read -p "Do you want to enable the generated sites? [y/N] " enable_sites

if [[ $enable_sites =~ ^[Yy]$ ]]; then
    # Enable the backend site and restart Apache
    if [ $choice -eq 1 ] || [ $choice -eq 3 ]; then
        sudo a2ensite "$backend_domain_name.conf"
    fi

    # Enable the frontend site and restart Apache if it was generated
    if [ "$enable_frontend" = true ]; then
        sudo a2ensite "$frontend_domain_name.conf"
    fi

    sudo systemctl restart apache2
else
    # Provide commands for the user to enable the sites and restart Apache manually
    if [ $choice -eq 1 ] || [ $choice -eq 3 ]; then
        echo "To enable $backend_domain_name.conf, run:"
        echo "sudo a2ensite $backend_domain_name.conf"
    fi

    # Show commands for enabling the frontend site if it was generated
    if [ "$enable_frontend" = true ]; then
        echo "To enable $frontend_domain_name.conf, run:"
        echo "sudo a2ensite $frontend_domain_name.conf"
    fi

    echo "To restart Apache, run:"
    echo "sudo systemctl restart apache2"
fi

echo "V-hosts generation completed."
