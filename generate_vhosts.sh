#!/bin/bash

echo "Do you want to generate v-hosts for [1] Backend, [2] Frontend or [3] Both?"
read choice

if [ $choice -lt 1 ] || [ $choice -gt 3 ]; then
    echo "Invalid choice"
    exit 1
fi

if [ $choice -eq 1 ] || [ $choice -eq 3 ]; then
    echo "Please enter the backend domain name:"
    read backend_domain_name

    echo "Please enter the backend site path:"
    read backend_site_path
fi

if [ $choice -eq 2 ] || [ $choice -eq 3 ]; then
    echo "Please enter the frontend domain name:"
    read frontend_domain_name

    echo "Please enter the frontend site path:"
    read frontend_site_path
fi

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

if [ $choice -eq 1 ] || [ $choice -eq 3 ]; then
    generate_backend > /etc/apache2/sites-available/$backend_domain_name.conf
fi

if [ $choice -eq 2 ] || [ $choice -eq 3 ]; then
    generate_frontend > /etc/apache2/sites-available/$frontend_domain_name.conf
fi

echo "V-hosts generated successfully"
