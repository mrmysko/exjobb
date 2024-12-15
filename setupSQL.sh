#!/bin/bash

# Usage: sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/mariadbSetup.sh)"

# Setup logging
LOG_FILE="/var/log/mariadb-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASSWORD="Linux4Ever"
ROOT_PASSWORD="Linux4Ever"

msg_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

msg_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
}

cleanup() {
    if [ "$1" != "0" ]; then
        msg_error "An error occurred during installation. Cleaning up..."
        systemctl stop mariadb.service
        apt -qq remove --purge mariadb-server -y
        rm -rf /var/lib/mysql
        rm -rf /etc/mysql
    fi
}

trap 'cleanup $?' EXIT

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    msg_error "Root privileges required"
    exit 1
fi

# Check if MariaDB is already installed
if systemctl is-active --quiet mariadb; then
    msg_error "MariaDB is already installed and running"
    exit 1
fi

# Create backup directory
BACKUP_DIR="/root/mariadb-setup-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup existing MariaDB configs if they exist
if [ -d "/etc/mysql" ]; then
    cp -r /etc/mysql "$BACKUP_DIR/"
fi

msg_info "Installing MariaDB"
if ! (apt -qq update && DEBIAN_FRONTEND=noninteractive apt -qq install -y mariadb-server); then
    msg_error "Failed to install MariaDB"
    exit 1
fi

# Enable and start MariaDB
msg_info "Starting MariaDB service"
systemctl start mariadb.service
systemctl enable mariadb.service

# Wait for MariaDB to be ready
msg_info "Waiting for MariaDB to be ready"
for i in {1..30}; do
    if mysqladmin ping &>/dev/null; then
        break
    fi
    sleep 1
done

if ! mysqladmin ping &>/dev/null; then
    msg_error "MariaDB failed to start properly"
    exit 1
fi

# Secure the MariaDB installation
mysql_secure_installation <<EOF

y
$ROOT_PASSWORD
$ROOT_PASSWORD
y
y
y
y
EOF

msg_info "Configuring database"
mysql -u root -p"${ROOT_PASSWORD}" <<EOF
-- Create new database and user
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';

-- Reload privileges
FLUSH PRIVILEGES;
EOF

msg_info "Configuring remote access and security settings"
cat >/etc/mysql/mariadb.conf.d/50-server.cnf <<EOF
[mysqld]
bind-address = 0.0.0.0
port = 3306

# Security settings
max_allowed_packet = 16M
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# Performance settings
key_buffer_size = 256M
max_connections = 100
innodb_buffer_pool_size = 256M
innodb_file_per_table = 1
innodb_flush_method = O_DIRECT
innodb_flush_log_at_trx_commit = 1

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mariadb-slow.log
long_query_time = 2
log_error = /var/log/mysql/error.log
EOF

# Create log directory if it doesn't exist
mkdir -p /var/log/mysql
chown mysql:mysql /var/log/mysql

# Restart MariaDB with new configuration
msg_info "Restarting MariaDB service"
if ! systemctl restart mariadb.service; then
    msg_error "Failed to restart MariaDB"
    exit 1
fi

# Verify database connection
if ! mysql -u"$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" "$DB_NAME" &>/dev/null; then
    msg_error "Failed to verify database connection"
    exit 1
fi

msg_info "MariaDB Setup Complete!"
msg_info "Database Name: $DB_NAME"
msg_info "Database User: $DB_USER"
msg_info "Remote access enabled on port 3306"
