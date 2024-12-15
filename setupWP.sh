#!/usr/bin/env bash

# Usage: sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/wpSetup.sh)"

# Get domain from realm
DOMAIN=$(realm list | grep -i "domain-name" | cut -d: -f2 | tr -d ' ')
SITE_NAME=$(hostname)

MYSQL_DATABASE="wordpress"
MYSQL_DB_HOST="sql.${DOMAIN}"
MYSQL_USER="wordpress"
WP_ADMIN_USER="wp_admin"
WP_ADMIN_PASS="Linux4Ever"
WP_PATH="/var/www/wordpress"

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

# Check if realm command exists and system is joined to a domain
if ! command -v realm &>/dev/null; then
    msg_error "realm command not found. Please install realmd package."
    exit 1
fi

if ! realm list &>/dev/null; then
    msg_error "System is not joined to a domain"
    exit 1
fi

# Install dependencies
msg_info "Installing dependencies"
if ! (apt -qq update && DEBIAN_FRONTEND=noninteractive apt -qq install -y \
    apache2 libapache2-mod-php php-mysql php-ldap php-mbstring php-gd php-curl \
    php-imagick php-xml php-zip php-intl); then
    msg_error "Failed to install dependencies"
    exit 1
fi

# Download and extract WordPress
msg_info "Downloading WordPress"
if ! wget -qO - https://wordpress.org/latest.tar.gz | tar -xz -C /var/www/; then
    msg_error "Failed to setup WordPress"
    exit 1
fi

msg_info "Setup WP-CLI"
wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

wp --allow-root --path="${WP_PATH}" config create --dbhost="${MYSQL_DB_HOST}" --dbuser="${MYSQL_USER}" --dbpass="${WP_ADMIN_PASS}" --dbname="${MYSQL_DATABASE}"
wp --allow-root --path="${WP_PATH}" core install --url="${SITE_NAME}.${DOMAIN}" --admin_email="admin@${DOMAIN}" --title="Homepage" --admin_user="${WP_ADMIN_USER}" --admin_password="${WP_ADMIN_PASS}"
wp --allow-root --path="${WP_PATH}" plugin install next-active-directory-integration
wp --allow-root --path="${WP_PATH}" plugin activate next-active-directory-integration
wp --allow-root --path="${WP_PATH}" plugin uninstall hello akismet

# Configure Apache
msg_info "Configuring Apache"
a2dissite 000-default.conf

# Create Apache configuration for WordPress
cat >/etc/apache2/sites-available/wordpress.conf <<EOF
<VirtualHost _default_:443>
    SSLEngine On
    SSLCertificateFile /etc/apache2/certs/wp-cert.pem
    SSLCertificateKeyFile /etc/apache2/certs/wp-key.pem
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

<VirtualHost *:80>
    Redirect 301 / https://$(hostname).${DOMAIN}
</VirtualHost>
EOF

# Enable required modules
a2enmod rewrite
a2enmod php
a2enmod ssl

# Enable WordPress site
a2ensite wordpress.conf

# Set proper permissions
msg_info "Setting permissions"
chown -R www-data:www-data "${WP_PATH}"
chmod -R 755 "${WP_PATH}"

# Generate certificate
mkdir /etc/apache2/certs
chmod 700 /etc/apache2/certs
openssl req -x509 -newkey rsa:4096 -keyout /etc/apache2/certs/wp-key.pem \
    -out /etc/apache2/certs/wp-cert.pem -sha256 -days 3560 -nodes \
    -subj "/C=SE/ST=Stockholm/L=Solna/O=DesignDreamers/OU=DD/CN=$(hostname).${DOMAIN}"

# Restart Apache
msg_info "Restarting Apache"
if ! systemctl restart apache2; then
    msg_error "Failed to restart Apache"
    exit 1
fi

msg_info "WordPress installation complete!"
