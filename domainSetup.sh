#!/usr/bin/env bash

# Todo - Config ubuntu pro and adsys
# Todo - Config ssh and ssh key in case of client=False

# Usage: sudo bash -c "${wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/domainSetup.sh}"

CLIENT=true
DOMAIN_USER="Administrator"
DOMAIN="Labb.se"
PERMIT_GROUP="Domain Users"
PERMIT_ADMIN="Domain Admins"

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
if ! apt update && apt install -y realmd sssd sssd-tools libnss-sss adcli; then
    msg_error "Failed to install dependencies"
    exit 1
fi

cat <<EOF >/etc/realmd.conf

[active-directory]
default-client = sssd
os-name = $NAME
os-version = $VERSION

[users]
default-home = /home/%D/%U

[$DOMAIN]
fully-qualified-names = Off

EOF

msg_info "Joining domain."
if ! realm join -U "$DOMAIN_USER" "$DOMAIN"; then
    msg_error "Failed to join domain"
    exit 1
fi

#msg_info "Change sssd conf"
#sed -i 's/fallback_homedir = .*/fallback_homedir = \/home\/%u/' /etc/sssd/sssd.conf
#sed -i 's/use_fully_qualified_names = .*/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
#systemctl restart sssd

msg_info "Enable pam_mkhomedir"
pam-auth-update --enable mkhomedir

msg_info "Changing login permissions"
realm deny --all
realm permit -g "$PERMIT_ADMIN"

if [[ $CLIENT ]]; then
    realm permit -g "$PERMIT_GROUP"
fi

#msg_info "Giving sudo to admins"
#SUDOERS_TEMP=$(mktemp)
#echo "%$(escape_spaces "${PERMIT_ADMIN}") ALL=(ALL) ALL" >"$SUDOERS_TEMP"
#visudo --check --quiet "$SUDOERS_TEMP" && mv "$SUDOERS_TEMP" /etc/sudoers.d/domain_sudoers

msg_info "Rebooting in 5 seconds..."
sleep 5
reboot
