# iRedMail Installation Guide — Ubuntu 22.04

![iRedMail Fast Install by dx4wrld](https://cdn.discordapp.com/attachments/1532368721174073498/1532369265041084457/content.png?ex=6a6c9996&is=6a6b4816&hm=26deb4607b34962679b5155992595a9aa46fa8a59e18a0883b299d203f99e3a9)

**Mail Server Deployment Guide**  
A complete step-by-step manual for installing iRedMail on Ubuntu 22.04.

*Compiled & automated by dx4wrld · Fast Run*

---


## Contents

1. [Introduction](#1-introduction)
2. [Prerequisites](#2-prerequisites)
3. [Manual Installation Steps](#3-manual-installation-steps)
   - [3.1 Set the Hostname](#31-set-the-hostname)
   - [3.2 Download and Run iRedMail](#32-download-and-run-iredmail)
   - [3.3 DNS Records (MX, SPF, DKIM, DMARC)](#33-dns-records-mx-spf-dkim-dmarc)
   - [3.4 Let's Encrypt SSL Certificates](#34-lets-encrypt-ssl-certificates)
   - [3.5 Testing the Mail Server](#35-testing-the-mail-server)
4. [Conclusion](#4-conclusion)

---

## 1. Introduction

iRedMail is a free, open-source mail server solution. It bundles everything needed to run a production-ready mail platform in one installer:

- Components for sending and receiving mail
- Storage
- Anti-spam and anti-virus protection
- Encrypted communication
- Web-based admin panel for managing domains and mailboxes

This guide covers the full manual installation of iRedMail on a fresh Ubuntu 22.04 server.

---

## 2. Prerequisites

- An **Ubuntu 22.04** server with at least **4 GB of RAM**
- At least two DNS **A records** pointing to the server's IP (e.g. `mail.example.com` and `example.com`)
- SSH access as a **non-root user** with `sudo` privileges
- An open support ticket with your hosting provider to **unblock SMTP port 25**
- An up-to-date system (`apt update` / `apt upgrade`)

---

## 3. Manual Installation Steps

### 3.1 Set the Hostname

```bash
sudo hostnamectl set-hostname mail.example.com
```

Edit the hosts file:

```bash
sudo nano /etc/hosts
```

Change the `127.0.1.1` line to:

```text
127.0.1.1 mail.example.com mail
```

Verify the active hostname:

```bash
hostname -f
# Expected output: mail.example.com
```

### 3.2 Download and Run iRedMail

```bash
wget https://github.com/iredmail/iRedMail/archive/refs/tags/1.7.3.tar.gz
tar -xvf 1.7.3.tar.gz
cd iRedMail-1.7.3
sudo apt update
sudo bash iRedMail.sh
```

During the setup wizard, confirm the following in order:

| Prompt | Action |
|--------|--------|
| Mail storage path | Press **Enter** (default `/var/vmail`) |
| Web server | Keep **Nginx** and press **Enter** |
| Backend for mailboxes | Arrow down + space to select **MariaDB** |
| LDAP suffix | Press **Enter** for the default domain-based format |
| MySQL root password | Enter a strong password |
| First domain | Enter your domain (e.g. `example.com`) |
| Postmaster admin password | Enter a strong password |
| Optional components | Select and confirm with **Enter** |
| Continue? `[y\|N]` | Type **Y** |
| iRedMail firewall rules (SSH port 22) | Type **Y** |
| Restart firewall now? | Type **Y** |

Once finished, reboot the server:

```bash
sudo systemctl reboot
```

### 3.3 DNS Records (MX, SPF, DKIM, DMARC)

Add the following records at your DNS provider:

| Type | Name | Value |
|------|------|-------|
| **MX** | `@` | `mail.example.com` (priority **10**) |
| **TXT** | `@` | `"v=spf1 a mx ip4:SERVER_IP -all"` |
| **TXT** | `dkim._domainkey` | Value from `sudo amavisd-new showkeys` |
| **TXT** | `_dmarc` | `"v=DMARC1; p=reject; rua=mailto:dmarc-reports@example.com; pct=100"` |

Verify the DKIM keys:

```bash
sudo amavisd-new testkeys
# Expected output: dkim._domainkey.example.com => pass
```

### 3.4 Let's Encrypt SSL Certificates

```bash
sudo snap install certbot --classic
sudo certbot certonly --webroot -w /opt/www/well_known \
  -d mail.example.com -m hello@example.com --agree-tos
```

Then update the certificate paths in these files, replacing the default iRedMail certificates with the Let's Encrypt ones:

- `/etc/nginx/sites-available/00-default-ssl.conf`
- `/etc/nginx/templates/ssl.tmpl`
- `/etc/postfix/main.cf`
- `/etc/dovecot/dovecot.conf`

Restart the services:

```bash
sudo systemctl restart nginx postfix dovecot
```

### 3.5 Testing the Mail Server

- **iRedAdmin**: https://mail.example.com/iredadmin  
  Log in as `postmaster`
- Create a new mailbox via **Add → User**
- **Webmail (Roundcube)**: https://mail.example.com/mail
- Send a test email between `postmaster` and the new mailbox
- Check the email headers for `dkim=pass`

---

## 4. Conclusion

Following this procedure gives you a fully installed and secured iRedMail mail server, with valid SPF, DKIM, and DMARC records in place.

---

*iRedMail Install Guide — prepared by dx4wrld*
