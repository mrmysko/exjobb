#!/usr/bin/env bash

# Usage: sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/wpSetup.sh)"

# Setup logging
LOG_FILE="/var/log/wp-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

msg_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

msg_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
}

cleanup() {
    if [ "$1" != "0" ]; then
        msg_error "An error occurred during installation. Cleaning up..."
        [ -f "/etc/apache2/sites-available/wordpress.conf" ] && rm -f "/etc/apache2/sites-available/wordpress.conf"
        [ -d "/etc/apache2/certs" ] && rm -rf "/etc/apache2/certs"
    fi
}

trap 'cleanup $?' EXIT

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

# Get domain from realm with error checking
DOMAIN=$(realm list | grep -i "domain-name" | cut -d: -f2 | tr -d ' ')
if [ -z "$DOMAIN" ]; then
    msg_error "Failed to extract domain from realm"
    exit 1
fi

# Validate hostname
SITE_NAME=$(hostname)
if ! echo "$SITE_NAME" | grep -qP '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'; then
    msg_error "Invalid hostname format: $SITE_NAME"
    exit 1
fi

# Database configuration (using fixed credentials)
MYSQL_DATABASE="wordpress"
MYSQL_DB_HOST="sql.${DOMAIN}"
MYSQL_USER="wordpress"
WP_ADMIN_PASS="Linux4Ever"
WP_ADMIN_USER="wp_admin"
WP_PATH="/var/www/wordpress"

# Create backup directory
BACKUP_DIR="/root/wp-setup-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup existing WordPress and Apache configs
if [ -d "${WP_PATH}" ]; then
    msg_info "Backing up existing WordPress installation"
    cp -r "${WP_PATH}" "${BACKUP_DIR}/"
    rm -rf "${WP_PATH}"
fi

if [ -f "/etc/apache2/sites-available/000-default.conf" ]; then
    cp /etc/apache2/sites-available/000-default.conf "$BACKUP_DIR/"
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

# Configure WordPress
wp --allow-root --path="${WP_PATH}" config create \
    --dbhost="${MYSQL_DB_HOST}" \
    --dbuser="${MYSQL_USER}" \
    --dbpass="${WP_ADMIN_PASS}" \
    --dbname="${MYSQL_DATABASE}" \
    --extra-php <<PHP
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);
define('FORCE_SSL_ADMIN', true);
define('DISALLOW_FILE_EDIT', true);
PHP

wp --allow-root --path="${WP_PATH}" core install \
    --url="${SITE_NAME}.${DOMAIN}" \
    --admin_email="admin@${DOMAIN}" \
    --title="${SITE_NAME} Homepage" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}"

wp --allow-root --path="${WP_PATH}" plugin install next-active-directory-integration
wp --allow-root --path="${WP_PATH}" plugin activate next-active-directory-integration
wp --allow-root --path="${WP_PATH}" plugin uninstall hello akismet

# Configure Apache
msg_info "Configuring Apache"
a2dissite 000-default.conf

# Create Apache configuration for WordPress with security headers
cat >/etc/apache2/sites-available/wordpress.conf <<EOF
<VirtualHost _default_:443>
    ServerName ${SITE_NAME}.${DOMAIN}
    SSLEngine On
    SSLCertificateFile /etc/apache2/certs/wp-cert.pem
    SSLCertificateKeyFile /etc/apache2/certs/wp-key.pem
    DocumentRoot /var/www/wordpress
    
    # Security headers
    Header set X-Content-Type-Options "nosniff"
    Header set X-Frame-Options "SAMEORIGIN"
    Header set X-XSS-Protection "1; mode=block"
    Header set Referrer-Policy "strict-origin-when-cross-origin"
    Header set Permissions-Policy "geolocation=(), microphone=(), camera=()"
    
    <Directory /var/www/wordpress>
        Options FollowSymLinks
        AllowOverride Limit Options FileInfo
        DirectoryIndex index.php
        Require all granted
        
        # Protect wp-config.php
        <Files wp-config.php>
            Require all denied
        </Files>
    </Directory>
    
    <Directory /var/www/wordpress/wp-content>
        Options FollowSymLinks
        Require all granted
        
        # Prevent direct access to PHP files in wp-content
        <FilesMatch "\.php$">
            Require all denied
        </FilesMatch>
    </Directory>
    
    # Prevent access to .htaccess and other hidden files
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>
</VirtualHost>

<VirtualHost *:80>
    ServerName ${SITE_NAME}.${DOMAIN}
    Redirect permanent / https://${SITE_NAME}.${DOMAIN}/
</VirtualHost>
EOF

# Enable required modules
a2enmod rewrite
a2enmod php
a2enmod ssl
a2enmod headers

# Enable WordPress site
a2ensite wordpress.conf

# Set proper permissions
msg_info "Setting permissions"
find "${WP_PATH}" -type d -exec chmod 755 {} \;
find "${WP_PATH}" -type f -exec chmod 644 {} \;
chown -R www-data:www-data "${WP_PATH}"

# Generate certificate
mkdir -p /etc/apache2/certs
chmod 700 /etc/apache2/certs
openssl req -x509 -newkey rsa:4096 -keyout /etc/apache2/certs/wp-key.pem \
    -out /etc/apache2/certs/wp-cert.pem -sha256 -days 3560 -nodes \
    -subj "/C=SE/ST=Stockholm/L=Solna/O=DesignDreamers/OU=DD/CN=${SITE_NAME}.${DOMAIN}"
chmod 600 /etc/apache2/certs/wp-key.pem
chmod 644 /etc/apache2/certs/wp-cert.pem

# Restart Apache
msg_info "Restarting Apache"
if ! systemctl restart apache2; then
    msg_error "Failed to restart Apache"
    exit 1
fi

msg_info "WordPress installation complete!"
msg_info "Site URL: https://${SITE_NAME}.${DOMAIN}"
msg_info "Admin URL: https://${SITE_NAME}.${DOMAIN}/wp-admin"
msg_info "Admin username: ${WP_ADMIN_USER}"
