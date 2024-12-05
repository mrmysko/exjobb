#!/usr/bin/env bash

# Usage: sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/linuxJoin.sh)"


DOMAIN_USER="TB-Anna-karinko"
INSTALL_SSH=false
DOMAIN=""

# Function to show usage
show_usage() {
    echo "Usage: $0 -domain DOMAIN_NAME [-server]"
    echo "Options:"
    echo "  -domain NAME    Specify the domain name (required)"
    echo "  -server        Install OpenSSH server"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -server)
            INSTALL_SSH=true
            DOMAIN_USER="T0-Stefanbo"
            shift
            ;;
        -domain)
            if [ -n "$2" ]; then
                DOMAIN="$2"
                shift 2
            else
                msg_error "Domain name is required for -domain parameter"
                show_usage
            fi
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            msg_error "Unknown parameter: $1"
            show_usage
            ;;
    esac
done

# Get system info
NAME=$(lsb_release -a 2>/dev/null | grep "Distributor ID:" | cut -f2)
VERSION=$(lsb_release -a 2>/dev/null | grep "Release:" | cut -f2)

msg_info() {
    echo "[INFO] $1"
}

msg_error() {
    echo "[ERROR] $1"
}

escape_spaces() {
    local text="$1"
    echo "${text// /\\ }"
}

# Check if domain is provided
if [ -z "$DOMAIN" ]; then
    msg_error "Domain parameter is required"
    show_usage
fi

if [ "$EUID" -ne 0 ]; then
    msg_error "Root required"
    exit 1
fi

msg_info "Setting up client"
msg_info "Using domain: $DOMAIN"

msg_info "Installing dependencies"
if ! (apt -qq update && DEBIAN_FRONTEND=noninteractive apt -qq install -y \
    realmd sssd sssd-tools libnss-sss adcli krb5-user adsys); then
    msg_error "Failed to install dependencies"
    exit 1
fi

cat <<EOF >/etc/realmd.conf

[active-directory]
default-client = sssd
os-name = $NAME
os-version = $VERSION

EOF

msg_info "Setting timezone"
if ! timedatectl set-timezone Europe/Stockholm; then
    msg_error "Failed to set timezone"
    exit 1
fi

msg_info "Configuring NTP"
sudo mkdir -p /etc/systemd/timesyncd.conf.d

sudo tee /etc/systemd/timesyncd.conf.d/windows-time.conf >/dev/null <<EOL
[Time]
NTP=time.windows.com
FallbackNTP=ntp.ubuntu.com
EOL

sudo systemctl restart systemd-timesyncd

msg_info "Joining domain."
if ! realm join -U "$DOMAIN_USER" "$DOMAIN"; then
    msg_error "Failed to join domain"
    exit 1

else
    msg_info "Successfully joined domain $DOMAIN"
fi

msg_info "Enabling pam_mkhomedir"
pam-auth-update --enable mkhomedir

# Enable Ubuntu Pro
msg_info "Enabling Ubuntu Pro"

# Prompt for token
while true; do
    read -p "Ubuntu Pro token: " TOKEN
    if [ -z "$TOKEN" ]; then
        msg_error "Token cannot be empty."
        continue
    fi

    if ! pro attach "$TOKEN"; then
        msg_error "Failed to activate Ubuntu Pro. Verify your token."
        read -p "Try again? [Y/N]: " RETRY
        if [[ "${RETRY:0:1}" =~ [Nn] ]]; then
            msg_error "Ubuntu Pro activation cancelled"
            break
        fi
        continue
    fi

    msg_info "Ubuntu Pro successfully activated"
    break
done

# Configure SSH
if [ "$INSTALL_SSH" = true ]; then
    msg_info "Installing OpenSSH Server"
    if ! DEBIAN_FRONTEND=noninteractive apt -qq install -y openssh-server; then
        msg_error "Failed to install OpenSSH Server"
        exit 1
    fi
    msg_info "OpenSSH Server installed successfully"
fi

# Restart
read -p "Domain Setup complete. Press ENTER to reboot..."
echo "Rebooting system in 5 seconds..."
for i in {5..1}; do
    echo -n "$i... "
    sleep 1
done
/sbin/reboot
