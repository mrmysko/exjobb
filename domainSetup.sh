#!/usr/bin/env bash

client=True
domain_user="Administrator"
domain="Labb.se"
permit_group="Domain Users"
permit_admin="Domain Admins"

escape_spaces() {
    local text="$1"
    echo "${text// /\\ }"
}

msg_info "Setting up client."

msg_info "Installing realmd."
apt install -y realmd

msg_info "Joining domain."
realm join -U "${domain_user}" "${domain}"

# Fix sssd conf, fallback home and fqdn

msg_info "Changing login permissions"
realm deny --all
realm permit -g "${permit_admin}"

if [[ ${client} ]]; then
    realm permit -g "${permit_group}"
fi

msg_info "Giving sudo for admins"
SUDOERS_TEMP=$(mktemp)

echo "%$(escape_spaces "${permit_admin}") ALL=(ALL) ALL" >"$SUDOERS_TEMP"
visudo -f "$SUDOERS_TEMP" && cp "$SUDOERS_TEMP" /etc/sudoers.d/custom_admins
rm "$SUDOERS_TEMP"

reboot
