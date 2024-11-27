#!/usr/bin/env bash

# Usage: sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/wpSetup.sh)"

msg_info() {
    echo "[INFO] $1"
}

msg_error() {
    echo "[ERROR] $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    msg_error "Root privileges required"
    exit 1
fi

# Install dependencies
msg_info "Installing dependencies"
if ! (apt -qq update && DEBIAN_FRONTEND=noninteractive apt -qq install -y \
    apache2 libapache2-mod-php php-mysql php-ldap); then
    msg_error "Failed to install dependencies"
    exit 1
fi

# Download and extract WordPress
msg_info "Downloading and extracting WordPress"
if ! wget -qO - https://wordpress.org/latest.tar.gz | tar -xz -C /var/www/; then
    msg_error "Failed to download or extract WordPress"
    exit 1
fi

# Set proper permissions
msg_info "Setting permissions"
chown -R www-data:www-data /var/www/wordpress
chmod -R 755 /var/www/wordpress

# Configure Apache
msg_info "Configuring Apache"
a2dissite 000-default.conf

# Enable required modules
a2enmod rewrite
a2enmod php

# Create Apache configuration for WordPress
cat > /etc/apache2/sites-available/wordpress.conf << 'EOF'
<VirtualHost *:80>
    DocumentRoot /var/www/wordpress
    <Directory /var/www/wordpress>
        Options FollowSymLinks
        AllowOverride Limit Options FileInfo
        DirectoryIndex index.php
        Require all granted
    </Directory>
    <Directory /var/www/wordpress/wp-content>
        Options FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Enable WordPress site
a2ensite wordpress.conf

# Restart Apache
msg_info "Restarting Apache"
if ! systemctl restart apache2; then
    msg_error "Failed to restart Apache"
    exit 1
fi

msg_info "WordPress installation completed successfully"