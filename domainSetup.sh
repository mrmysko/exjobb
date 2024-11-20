#!/usr/bin/env bash

# Todo - Config ubuntu pro and adsys
# Todo - Config ssh and ssh key in case of client=False

# Usage: sudo bash -c "${wget -qLO - https://raw.githubusercontent.com/mrmysko/exjobb/refs/heads/main/domainSetup.sh}"

client=True
domain_user="Administrator"
domain="Labb.se"
permit_group="Domain Users"
permit_admin="Domain Admins"

msg_info() {
    echo "[INFO] $1"
}

escape_spaces() {
    local text="$1"
    echo "${text// /\\ }"
}

if [ "$EUID" -ne 0 ]; then
    echo "Root required"
    exit 1
fi

msg_info "Setting up client"

msg_info "Installing dependencies"
apt update && apt install -y realmd sssd sssd-tools libnss-sss adcli

msg_info "Joining domain."
realm join -U "${domain_user}" "${domain}"

msg_info "Change sssd conf"
sed -i 's/fallback_homedir = .*/fallback_homedir = \/home\/%u/' /etc/sssd/sssd.conf
sed -i 's/use_fully_qualified_names = .*/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
systemctl restart sssd

msg_info "Enable pam_mkhomedir"
pam-auth-update --enable mkhomedir

msg_info "Changing login permissions"
realm deny --all
realm permit -g "${permit_admin}"

if [[ ${client} ]]; then
    realm permit -g "${permit_group}"
fi

#msg_info "Giving sudo to admins"
#SUDOERS_TEMP=$(mktemp)
#echo "%$(escape_spaces "${permit_admin}") ALL=(ALL) ALL" >"$SUDOERS_TEMP"
#visudo --check --quiet "$SUDOERS_TEMP" && mv "$SUDOERS_TEMP" /etc/sudoers.d/domain_sudoers

msg_info "Rebooting in 5 seconds..."
sleep 5
reboot
