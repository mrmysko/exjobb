
BrewIT är ett nystartat företag med inriktning på att bygga IT-miljöer. Vi kan det mesta inom serverhantering och nätverkslösningar, vi skapar din IT-miljö med god säkerhet till ett lågt pris.

BrewIT har haft en god diskussion med Design Dreamers och därför lämnar vi en offert för att Design Dreamers ska kunna expandera sin verksamhet.

I dagsläget har Design Dreamers en miljö med tre Linuxbaserade datorer och en Linux server. Design Dreamers har planer på att utöka sin miljö till att även omfatta Windows datorer, då nyanställda förväntas kunna hantera dessa lättare.
Vi på BrewIT föreslår en lösning med två maskiner med virtuella servrar på, då är det möjligt att ha olika servrar med olika operativsystem och roller, till en lägre kostnad.

Server 1: virtuella servrar: AD, databas

Server 2: viruella servrar: AD, wordpress
två nätverkskort så hemsidan hamnar på ett separat DMZ

Linuxdatorer ansluter genom ett script som installerar och ansluter datorn till domänen.
Program som används är: realmd, sssd, sssd-tools, libnss-sss, adcli, krb5-user, adsys.

Användare importeras med ett script från listan över anställda så alla får varsitt konto. Även särskilda konton för administration av miljön skapas.

Strukturen i AD ser ut såhär: "bild"

Företagsmail hanteras i Azure
