#!/usr/bin/env bash

cat <<'EOF' >/etc/polkit-1/rules.d/49-ubuntu-admin.rules
polkit.addAdminRule(function(action, subject) {
	return ["unix-group:T1_Admins@DD.COM"];
});
EOF
