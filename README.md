# Projekt - Linux AD Integrering

Det här projektet är till för att försöka AD-integrera Linux-klienter och servrar i en Windows-miljö.

Det finns två stycken fysiska servrar med Windows Server 2022 (Standard licens) som kör två virtuella maskiner vardera.

**De virtuella servrarna är:**
    <ui>
    <li>DC1 (Windows Server 2022)</li>
    <li>DC2 (Windows Server 2022)</li>
    <li>SQL (Ubuntu Server 22.04)</li>
    <li>Wordpress (Ubuntu Server 22.04)</li>
    </ul>

Linux-servrarna ska administreras med admin-konton från AD.

Användarna med Linux-klienter ska logga in med sina AD-credentials, och det ska finnas en admingrupp i AD som har sudo rättigheter på dem.

Wordpress-siten ska integreras så att användare kan logga in med sina AD-konton.
