|Error|Fix|
|---|---|
|[Ubuntu 24.04 hangs on AD join (Unresolved)](https://bugs.launchpad.net/subiquity/+bug/2069437)|Use realmd to AD join after install|
|AD not updating DNS Records on Linux join|
|Home directory not created on first login|Use: ```pam-auth-update --enable mkhomedir```|