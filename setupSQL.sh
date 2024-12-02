#!/bin/bash

# Usage: sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/mariadbSetup.sh)"

DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASSWORD="Linux4Ever"
ROOT_PASSWORD="Linux4Ever"

msg_info() {
    echo "[INFO] $1"
}

msg_error() {
    echo "[ERROR] $1"
}

if [ "$EUID" -ne 0 ]; then
    msg_error "Root required"
    exit 1
fi

msg_info "Installing MariaDB"
if ! (apt -qq update && DEBIAN_FRONTEND=noninteractive apt -qq install mariadb-server); then
    msg_error "Failed to install mariadb"
    exit 1
fi

systemctl start mariadb
systemctl enable mariadb

msg_info "Configuring database"
mysql -u root <<EOF
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASSWORD';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disable remote root login
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Create new database and user
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';

-- Reload privileges
FLUSH PRIVILEGES;
EOF

msg_info "Configuring remote access"
cat >/etc/mysql/mariadb.conf.d/50-server.cnf <<EOF
[mysqld]
bind-address = 0.0.0.0
port = 3306
EOF

if ! systemctl restart mariadb.service; then
    msg_error "Failed to restart MariaDB"
    exit 1
fi

msg_info "MariaDB Setup Complete!"
