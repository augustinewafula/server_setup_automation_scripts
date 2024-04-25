#!/bin/bash

CONFIG_FILE="config.txt"

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
    local backend_domain_name=$1
    local backend_site_path=$2

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
    local frontend_domain_name=$1
    local frontend_site_path=$2

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

enable_https() {
    read -p "Do you want to enable HTTPS on the created sites? [y/N] " enable_https
    if [[ $enable_https =~ ^[Yy]$ ]]; then
        # Enable HTTPS using certbot for backend site
        if [ $choice -eq 1 ] || [ $choice -eq 3 ]; then
            sudo certbot --apache -d "$backend_domain_name"
        fi

        # Enable HTTPS using certbot for frontend sites if they were generated
        for ((i=1; i<=2; i++)); do
            if [ "${enable_frontends[$((i-1))]}" = true ]; then
                sudo certbot --apache -d "${frontend_domain_names[$((i-1))]}"
            fi
        done
    else
        echo "Skipping HTTPS enablement."
    fi
}

enable_frontends=(false false)
frontend_domain_names=()

echo "Do you want to generate v-hosts for [1] Backend, [2] Frontend 1, [3] Frontend 2, or [4] All?"
read -p "Please enter the number corresponding to your choice: " choice

if [ $choice -lt 1 ] || [ $choice -gt 4 ]; then
    echo "Invalid choice"
    exit 1
fi

if [ $choice -eq 1 ] || [ $choice -eq 4 ]; then
    backend_domain_name=$(read_value "backend_domain_name")
    backend_site_path=$(read_value "backend_site_path")

    save_config "$backend_domain_name" "$(generate_backend "$backend_domain_name" "$backend_site_path")"
fi

for ((i=1; i<=2; i++)); do
    if [ $choice -eq $((i+1)) ] || [ $choice -eq 4 ]; then
        enable_frontends[$((i-1))]=true

        frontend_domain_name=$(read_value "frontend${i}_domain_name")
        frontend_site_path=$(read_value "frontend${i}_site_path")
        frontend_domain_names+=("$frontend_domain_name")

        save_config "$frontend_domain_name" "$(generate_frontend "$frontend_domain_name" "$frontend_site_path")"
    fi
done

echo "V-hosts generation completed."

# Ask if the user wants to enable the sites
read -p "Do you want to enable the generated sites? [y/N] " enable_sites

if [[ $enable_sites =~ ^[Yy]$ ]]; then
    # Enable the backend site and restart Apache
    if [ $choice -eq 1 ] || [ $choice -eq 4 ]; then
        echo "Enabling $backend_domain_name.conf..."
        sudo a2ensite "$backend_domain_name.conf"
    fi

    # Enable the frontend sites and restart Apache if they were generated
    for ((i=1; i<=2; i++)); do
        if [ "${enable_frontends[$((i-1))]}" = true ]; then
            echo "Enabling ${frontend_domain_names[$((i-1))]}.conf..."
            sudo a2ensite "${frontend_domain_names[$((i-1))]}.conf"
        fi
    done

    sudo systemctl restart apache2

    # Ask if the user wants to enable HTTPS
    enable_https
else
    # Provide commands for the user to enable the sites and restart Apache manually
    if [ $choice -eq 1 ] || [ $choice -eq 4 ]; then
        echo "To enable $backend_domain_name.conf, run:"
        echo "sudo a2ensite $backend_domain_name.conf"
    fi

    # Show commands for enabling the frontend sites if they were generated
    for ((i=1; i<=2; i++)); do
        if [ "${enable_frontends[$((i-1))]}" = true ]; then
            echo "To enable ${frontend_domain_names[$((i-1))]}.conf, run:"
            echo "sudo a2ensite ${frontend_domain_names[$((i-1))]}.conf"
        fi
    done

    echo "To restart Apache, run:"
    echo "sudo systemctl restart apache2"

    # Ask if the user wants to enable HTTPS
    enable_https
fi

echo "V-hosts generation and HTTPS enablement completed."