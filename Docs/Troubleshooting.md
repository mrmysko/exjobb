|Error|Cause|Fix|
|---|---|---|
|[Ubuntu 24.04 hangs on AD join (Unresolved)](https://bugs.launchpad.net/subiquity/+bug/2069437)||Use realmd to AD join after install|
|AD not updating DNS Records on Linux join||
|Home directory not created on first login||Use: ```pam-auth-update --enable mkhomedir```|
|Users on clients can't change settings|SSSD conf specifies use_fully_qualified_names = False, but profiles are created with FQDN|
|RPC Server is unavailable||
|(SSH) Permission denied (gssapi-with-mic)||
|Gnome Local Password Auth|[Gnome use PolKit](https://serverfault.com/a/998597)||
|WordPress Publish, "Updating failed. The response is not a valid JSON response"|||
|PolicyDefinitions Permission Denied|Trying to copy files to the domain-shared SYSVOL|Copy files to the local SYSVOL folder|
