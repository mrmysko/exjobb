#!/usr/bin/env bash

# Todo - Config ssh and ssh key in case of client=False

# Usage: sudo bash -c "${wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/domainSetup.sh}"

DOMAIN_USER="Administrator"
DOMAIN="Labb.se"

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

if [ "$EUID" -ne 0 ]; then
    msg_error "Root required"
    exit 1
fi

msg_info "Setting up client"

msg_info "Installing dependencies"
if ! (apt -qq update && apt -qq install -y realmd sssd sssd-tools libnss-sss adcli krb5-user); then
    msg_error "Failed to install dependencies"
    exit 1
fi

cat <<EOF >/etc/realmd.conf

[active-directory]
default-client = sssd
os-name = $NAME
os-version = $VERSION

[users]
default-home = /home/%d/%u

EOF

msg_info "Joining domain."
if ! realm join -U "$DOMAIN_USER" "$DOMAIN"; then
    msg_error "Failed to join domain"
    exit 1

else
    msg_info "Successfully joined domain $DOMAIN"
fi

msg_info "Changing sssd conf"
sed -i 's/use_fully_qualified_names = .*/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
systemctl restart sssd

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
            exit 1
        fi
        continue
    fi

    msg_info "Ubuntu Pro successfully activated"
    break
done

# Restart
read -p "Domain Setup complete. Press ENTER to reboot..."
echo "Rebooting system in 5 seconds..."
for i in {5..1}; do
    echo -n "$i... "
    sleep 1
done
/sbin/reboot
