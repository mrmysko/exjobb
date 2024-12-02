|Desc|Command|
|---|---|
|Join domain|```realm join -U <user> <domain>```|
|Discover domain|```realm discover <domain>```|
|Check domain status #1|```realm list <domain>```|
|Check domain status #2|```sssctl domain-status <domain>```|
|Query entries from databases configured in nsswitch.conf|```getent <entry> <object>```|
|Check applied policies|```adsysctl policy applied```|
|Set IP address|```New-NetIPAddress -IPAddress "ip" -InterfaceAlias “Ethernet” -DefaultGateway "ip" -AddressFamily IPv4 -PrefixLength "len"```|
|Rename computer|```Rename-Computer -NewName "name"```|
|Remove routes|```Remove-NetRoute -InterfaceAlias "Ethernet"```|
|Remove IP Address|```Remove-NetIPAddress -InterfaceAlias "ethernet"```|

adcli - Perform actions in Active Directory

wbinfo - Winbind query tool.

(Windows) setspn - Reads, modifies, and deletes the Service Principal Names (SPN) directory property for an Active Directory service account.
