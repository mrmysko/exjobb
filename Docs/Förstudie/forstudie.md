# Förarbete

## Vilka är vi?

<img src="./BrewIT.png" alt="drawing" width="200"/>

BrewIT är ett nystartat företag grundat av två entusiaster med inriktning på att bygga IT-miljöer. Med bred kompetens inom serverhantering och nätverkslösningar levererar vi skräddarsydda, säkra och kostnadseffektiva lösningar som möter våra kunders behov.

Tillsammans med oss får ni en IT-miljö som inte bara är robust och pålitlig, utan också anpassad för framtidens behov.

## Varför lämnar vi offert?

Under en trevlig afterwork träffade vi Stefan, Anna-Karin och Charlie, grundarna av det nystartade företaget DesignDreamers. Efter att ha drivit webbdesign som en hobby under en tid fick de sitt första riktiga uppdrag – att designa en hemsida åt ett externt företag. Detta blev startskottet för att omvandla deras passion till ett professionellt företag.

Men med den här omställningen kommer nya krav. Deras tidigare hobbybaserade IT-lösning är inte längre tillräcklig för att stödja deras växande verksamhet. För att hantera det ökade arbetsflödet och möjliggöra framtida expansion behöver de en skalbar och pålitlig IT-miljö som kan möta deras nuvarande och kommande behov.

Efter en givande diskussion med DesignDreamers har BrewIT tagit fram en offert som fokuserar på att bygga en säker och robust IT-infrastruktur. Vår lösning hjälper dem att ta nästa steg i sin resa – från hobbyprojekt till ett framgångsrikt och professionellt företag.

## Behov/Önskemål

DesignDreamers har specificerat följande behov och önskemål för sin framtida IT-miljö:

**Central identitetshantering:** En lösning för att hantera användaridentiteter och autentisering på ett centraliserat och säkert sätt.

**Behålla befintliga Linux-datorer:** Deras nuvarande Linux-baserade arbetsstationer ska fortsätta användas som en del av den nya miljön.

**Möjlighet att använda Windows-datorer:** Flexibilitet att lägga till och använda Windows-datorer i IT-miljön.

**Enhetlig autentisering:** Möjlighet för användare att logga in med samma konto för åtkomst till flera tjänster, vilket förbättrar användarupplevelsen och effektiviteten.

**Kostnadseffektivitet:** Maximal återanvändning av befintlig IT-utrustning för att hålla kostnaderna nere.

## Nuläge

DesignDreamers nuvarande IT-miljö består av:

<ol>
<li>Tre Linuxbaserade arbetsstationer.</li>
<li>Två Linuxbaserade servrar:</li>
<ul>
<li>Databasserver – Hanterar data för WordPress.
<li>Webbserver – Presentation av designer.
</ul>
</ol>

De har förberett ett nytt kontor i Solna med tillräckligt utrymme för alla anställda. Kontoret är redo att stödja verksamheten och tillväxten framöver. Det är utrustat med en snabb fiberanslutning på 250/250 Mbit.

## Vår lösning

För att optimera befintliga resurser och skapa en skalbar IT-miljö föreslår vi på BrewIT följande lösning:

<ol>
<li>Virtualisering av befintliga servrar:

De två nuvarande fysiska servrarna kommer att virtualiseras, vilket möjliggör flera virtuella servrar på samma hårdvara. Detta maximerar nyttjandet av befintliga resurser och minskar behovet av nya investeringar.</li>

<li>Integration av Linux-klienter:

Användare med Linux-datorer kan fortsätta arbeta med sina nuvarande enheter, men övergår till centralt administrerade användarkonton. Vi tillhandahåller en lösning för att ansluta Linux-datorerna till företagets interna nätverk för att förbättra säkerhet och kontroll.</li>

<li>Förbättrad nätverkssäkerhet:

För att skydda företagets interna miljö och webbservern mot externa hot införskaffas en dedikerad brandvägg och ett extra nätverkskort till webbservern. Dessa åtgärder kommer att säkerställa att den är logiskt åtskild från företagets övriga nätverk.</li>

<li>Licenshantering för Linux-klienter:

För att möjliggöra central administration av Linux-klienter behöver dessa utrustas med en Ubuntu Pro-prenumerationslicens, vilket även inkluderar säkerhets- och kompatibilitetsuppdateringar.</li>

<li>Windows Server som host-OS och licenshantering:

De fysiska servrarna kommer att använda Windows Server Standard som host-operativsystem. Valet av Windows motiveras av att några av de virtuella servrarna ändå kräver Windows-licens, och en standardlicens inkluderar licenser för dessa också; vilket gör detta till en kostnadseffektiv och praktisk lösning.

Utöver detta behöver varje klient som ansluter till Windows Server en **Client Access License (CAL)**, vilket säkerställer korrekt licensiering för klienternas åtkomst till servern.</li>

Denna lösning kombinerar återbruk, kostnadseffektivitet och förbättrad säkerhet.

## Teknisk specifikation

DesignDreamers erbjuds en säker och robust IT-miljö som omfattar två domänkontrollanter som kontinuerligt replikerar mellan varandra för att säkerställa hög tillgänglighet och felsäkerhet. Lösningen inkluderar också en databasserver för att hantera WordPress-data.

Webbservern med WordPress är placerad i en DMZ (Demilitarized Zone) för att isolera den från företagets interna nätverk. För att komplettera säkerheten installeras en brandvägg för att motverka intrång och skydda hela företagets IT-miljö.

**Serverkonfiguration:**

- **Server 1:**
  - **Operativsystem:** Windows Server 2022 Standard
  - **Virtuella maskiner:**
    - **VM1:** Domänkontrollant 1 – Windows Server 2022 Standard
    - **VM2:** Databasserver – Ubuntu Server 22.04 LTS
- **Server 2:**
  - **Operativsystem:** Windows Server 2022 Standard
  - **Virtuella maskiner:**
    - **VM1:** Domänkontrollant 2 – Windows Server 2022 Standard
    - **VM2:** WordPress-server – Ubuntu Server 22.04 LTS
  - **Extra:** Ett extra nätverkskort för DMZ-konfiguration

- **Brandvägg:**
  - **Modell:** "Modell tbd"

**AD-Struktur:**

Varje tier har dedikerade administratörskonton som är strikt isolerade från att logga in på resurser i andra tiers, vilket minskar risken för spridning av potentiella hot.

"Bild"

- **Tier 0: Kritiska resurser**
  - **Innehåll:** Domänkontrollanter och andra affärskritiska resurser.
    **- Administratörsroller:** Tier 0-administratörer har fullständig kontroll över domänen och hanterar resurser som utgör kärnan i IT-miljön. Dessa konton har den högsta nivån av säkerhet och åtkomstbegränsningar.

- **Tier 1: Applikations- och dataservrar**
  - **Innehåll:** WordPress-servern och databasservern.
  - **Administratörsroller:** Tier 1-administratörer hanterar specifikt dessa servrar, inklusive administration av applikationer, databaser och innehåll, utan åtkomst till Tier 0-resurser.

- **Tier Base: Användare och klienter**
  - **Innehåll:** Användarkonton och klientenheter (t.ex. datorer och mobila enheter).
  - **Administratörsroller:** Administratörer i Tier Base ansvarar för användarhantering, inklusive grupptillhörighet, lösenordshantering samt skapande och borttagning av användarkonton. De har endast åtkomst till resurser och enheter i denna tier.

**Wordpress:**

WordPress-servern hanteras av Tier 1-administratörer, som har full tillgång till serverns operativsystem samt administratörsbehörighet inom WordPress-applikationen.

För att integrera WordPress med företagets Active Directory används tillägget Next Active Directory Integration.

**Script:**

Vid överlämning tillhandahåller vi samtliga script som använts för att sätta upp servrar och klienter.

- Dessa inkluderar:

  - **Användarimport:**
    Script för att importera användare från en fördefinierad CSV-fil direkt till Active Directory.
  - **Linux-klientkonfiguration:**
    Script för att konfigurera Linux-klienter att ansluta till domänen med hjälp av realmd och sssd.
    För Linux-klienter krävs en Ubuntu Pro-licens för att möjliggöra tillämpning av GPO:er från Active Directory.

Utöver scripten lämnar vi också över en utförlig teknisk dokumentation som beskriver hur IT-miljön är konfigurerad. Dokumentationen fungerar som en guide för att förstå och underhålla infrastrukturen, och ger DesignDreamers möjlighet att bygga vidare på miljön och anpassa den efter framtida behov.
