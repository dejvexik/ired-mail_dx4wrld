# install_iredmail.sh — Automated iRedMail Installer (Ubuntu 22.04)

![iRedMail Fast Install by dx4wrld](https://cdn.discordapp.com/attachments/1532368721174073498/1532369265041084457/content.png?ex=6a6c9996&is=6a6b4816&hm=26deb4607b34962679b5155992595a9aa46fa8a59e18a0883b299d203f99e3a9)

**Automated Deployment Script**
Popis a návod na použitie skriptu `install_iredmail.sh`, ktorý automaticky nainštaluje iRedMail (aktuálna stabilná verzia **1.8.4**) na čistý server Ubuntu 22.04.

*Compiled & automated by dx4wrld · Fast Run*

---

## Obsah

1. [Čo skript robí](#1-čo-skript-robí)
2. [Požiadavky](#2-požiadavky)
3. [Nastavenie premenných](#3-nastavenie-premenných)
4. [Spustenie](#4-spustenie)
5. [Priebeh inštalácie krok za krokom](#5-priebeh-inštalácie-krok-za-krokom)
6. [Bezpečnostné kontroly v skripte](#6-bezpečnostné-kontroly-v-skripte)
7. [Čo urobiť po reštarte](#7-čo-urobiť-po-reštarte)
8. [Riešenie problémov](#8-riešenie-problémov)

---

## 1. Čo skript robí

`install_iredmail.sh` automatizuje celú manuálnu inštaláciu iRedMail pomocou nástroja `expect`, ktorý simuluje odpovede na interaktívneho sprievodcu `iRedMail.sh`. Skript:

- nastaví hostname servera,
- upraví `/etc/hosts`,
- aktualizuje systém (`apt update && apt upgrade`),
- stiahne a rozbalí najnovšiu stabilnú verziu iRedMail (**1.8.4**) z oficiálneho GitHub repozitára,
- automaticky prejde inštalačným wizardom (Nginx, MariaDB, doména, heslá, firewall),
- reštartuje server,
- na konci vypíše prehľadný súhrn s DNS záznamami, Let's Encrypt príkazmi a zoznamom potrebných portov.

---

## 2. Požiadavky

- Čistý server **Ubuntu 22.04**, min. **4 GB RAM**
- Neroot používateľ so `sudo` právami
- Aspoň dva DNS **A záznamy** smerujúce na IP servera (napr. `mail.example.com` a `example.com`)
- Odblokovaný port **25** u poskytovateľa hostingu (support ticket)
- Otvorené porty podľa sekcie [Required Ports](#7-čo-urobiť-po-reštarte) — buď priamo na serveri (VPS), alebo cez port forwarding na routeri (domáca/firemná sieť)

---

## 3. Nastavenie premenných

Pred spustením je nutné upraviť sekciu `SETTINGS` na začiatku súboru:

```bash
MAIL_HOSTNAME="mail.example.com"        # FQDN mailservera
MAIN_DOMAIN="example.com"               # vaša doména
SERVER_IP="192.0.2.1"                   # verejná IP servera (pre SPF)
MYSQL_ROOT_PASSWORD="ChangeThisPassword1!"
POSTMASTER_PASSWORD="ChangeThisPassword2!"
IREDMAIL_VERSION="1.8.4"                # aktuálna stabilná verzia
```

> **Dôležité:** heslá nesmú obsahovať znaky `"`, `\`, `$`, `[` ani `]` — skript to pred spustením overí a v prípade problému sa hneď zastaví so zrozumiteľnou chybou.

---

## 4. Spustenie

```bash
sudo bash install_iredmail.sh
```

Skript beží plne automaticky — nie je potrebné nič odklikávať manuálne. Priebeh trvá spravidla 10–20 minút v závislosti od rýchlosti servera a internetového pripojenia.

---

## 5. Priebeh inštalácie krok za krokom

| Krok | Čo sa deje |
|------|------------|
| 1/9 | Nastavenie hostname |
| 2/9 | Úprava `/etc/hosts` |
| 3/9 | `apt update` + `apt upgrade` |
| 4/9 | Inštalácia `expect`, `wget`, `tar` |
| 5/9 | Stiahnutie a rozbalenie iRedMail 1.8.4, kontrola integrity archívu |
| 6/9 | Automatizovaný beh `iRedMail.sh` cez `expect` (web server Nginx, MariaDB backend, predvolený LDAP suffix, MySQL root heslo, doména, heslo administrátora, voliteľné komponenty, potvrdenie, firewall pravidlá) |
| 7/9 | Reštart servera |
| 8/9 | Pripomienka nastaviť DNS záznamy |
| 9/9 | Výpis inštrukcií pre Let's Encrypt certifikáty a potrebné porty |

Každý krok v `expect` bloku má nastavený **20-minútový timeout** — ak sa nejaký prompt nezobrazí (napr. kvôli zmene textu vo wizarde v budúcej verzii), skript sa zastaví so zrozumiteľnou hláškou namiesto toho, aby visel donekonečna.

---

## 6. Bezpečnostné kontroly v skripte

- Kontrola hesiel na nebezpečné znaky pred spustením `expect` bloku.
- Kontrola, že sa archív skutočne stiahol (neprázdny súbor).
- Kontrola, že po rozbalení existuje `iRedMail.sh`.
- `set -euo pipefail` — skript sa okamžite zastaví pri akejkoľvek neočakávanej chybe.

---

## 7. Čo urobiť po reštarte

Po reštarte servera skript vypíše kompletný súhrn, ktorý obsahuje:

**DNS záznamy** (MX, SPF, DKIM, DMARC) — treba ich pridať u DNS providera.

**Let's Encrypt certifikát:**

```bash
sudo snap install certbot --classic
sudo certbot certonly --webroot -w /opt/www/well_known \
  -d mail.example.com -m hello@example.com --agree-tos
```

**Potrebné porty** (server aj router/NAT):

| Port | Protokol | Účel |
|------|----------|------|
| 22 | TCP | SSH |
| 25 | TCP | SMTP |
| 80 | TCP | HTTP (Let's Encrypt, redirect) |
| 443 | TCP | HTTPS (webmail, iRedAdmin) |
| 110 / 995 | TCP | POP3 / POP3S |
| 143 / 993 | TCP | IMAP / IMAPS |
| 587 | TCP | SMTP Submission |
| 465 | TCP | SMTPS |
| 4190 | TCP | ManageSieve (voliteľné) |

Ak je server za domácim/firemným routerom, tieto porty treba presmerovať cez **Port Forwarding / NAT** na lokálnu IP servera.

**Prístup po inštalácii:**

- iRedAdmin: `https://mail.example.com/iredadmin`
- Webmail: `https://mail.example.com/mail`

---

## 8. Riešenie problémov

- **Skript sa zastaví s hláškou `TIMEOUT waiting for ... prompt`** → text daného kroku vo wizarde sa v novšej verzii iRedMail zmenil. Spustite inštaláciu manuálne: `sudo bash iRedMail.sh` a prejdite krokmi ručne.
- **`ERROR: Download failed or file is empty`** → skontrolujte, či `IREDMAIL_VERSION` zodpovedá aktuálnej verzii na [iredmail.org/download.html](https://www.iredmail.org/download.html), a či má server prístup na internet.
- **Port 25 nefunguje ani po nastavení** → mnohí poskytovatelia (hosting aj domáci ISP) blokujú port 25 kvôli spamu — je potrebné požiadať o jeho odblokovanie cez support ticket.

---

*install_iredmail.sh — prepared by dx4wrld*
