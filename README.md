# install_iredmail.sh — Automated iRedMail Installer (Ubuntu 22.04)

![iRedMail Fast Install by dx4wrld](https://cdn.discordapp.com/attachments/1532368721174073498/1532369265041084457/content.png?ex=6a6c9996&is=6a6b4816&hm=26deb4607b34962679b5155992595a9aa46fa8a59e18a0883b299d203f99e3a9)

**Automated deployment script**
Documentation for `install_iredmail.sh`, which automatically installs iRedMail (current stable release **1.8.4**) on a fresh Ubuntu 22.04 server.

*Compiled & automated by dx4wrld · Fast Run*

---

## Contents

1. [What the script does](#1-what-the-script-does)
2. [Requirements](#2-requirements)
3. [Configuring the variables](#3-configuring-the-variables)
4. [Running it](#4-running-it)
5. [Installation walkthrough, step by step](#5-installation-walkthrough-step-by-step)
6. [Safety checks built into the script](#6-safety-checks-built-into-the-script)
7. [After the reboot](#7-after-the-reboot)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. What the script does

`install_iredmail.sh` automates the entire manual iRedMail installation using `expect`, which simulates the answers to the interactive `iRedMail.sh` wizard. The script:

- sets the server hostname,
- updates `/etc/hosts`,
- updates the system (`apt update && apt upgrade`),
- downloads and extracts the current stable iRedMail release (**1.8.4**) from the official GitHub repository,
- automatically walks through the installer wizard (Nginx, MariaDB, domain, passwords, firewall),
- reboots the server,
- prints a full summary at the end with DNS records, Let's Encrypt commands, and the list of required ports.

## 2. Requirements

- A fresh **Ubuntu 22.04** server with at least **4 GB RAM**
- A non-root user with `sudo` privileges
- At least two DNS **A records** pointing to the server's IP (e.g. `mail.example.com` and `example.com`)
- Port **25** unblocked by your hosting provider (support ticket)
- Required ports open — see [After the reboot](#7-after-the-reboot) — either directly on the server (VPS) or via port forwarding on your router (home/office network)

## 3. Configuring the variables

Before running the script, edit the `SETTINGS` section at the top of the file:

```bash
MAIL_HOSTNAME="mail.example.com"        # mail server FQDN
MAIN_DOMAIN="example.com"               # your domain
SERVER_IP="192.0.2.1"                   # server's public IP (for SPF)
MYSQL_ROOT_PASSWORD="ChangeThisPassword1!"
POSTMASTER_PASSWORD="ChangeThisPassword2!"
IREDMAIL_VERSION="1.8.4"                # current stable release
```

> **Important:** passwords must not contain `"`, `\`, `$`, `[`, or `]` — the script checks this before running and stops immediately with a clear error if it finds one.

## 4. Running it

```bash
sudo bash install_iredmail.sh
```

The script runs fully unattended — no manual clicking through prompts is needed. It typically takes 10–20 minutes depending on server and network speed.

## 5. Installation walkthrough, step by step

| Step | What happens |
|------|------------|
| 1/9 | Set the hostname |
| 2/9 | Update `/etc/hosts` |
| 3/9 | `apt update` + `apt upgrade` |
| 4/9 | Install `expect`, `wget`, `tar` |
| 5/9 | Download and extract iRedMail 1.8.4, verify archive integrity |
| 6/9 | Automated `iRedMail.sh` run via `expect` (Nginx web server, MariaDB backend, default LDAP suffix, MySQL root password, domain, admin password, optional components, confirmation, firewall rules) |
| 7/9 | Reboot the server |
| 8/9 | Reminder to set up DNS records |
| 9/9 | Print Let's Encrypt instructions and required ports |

Every step inside the `expect` block has a **20-minute timeout** — if a prompt doesn't appear (e.g. because a future iRedMail release changes the wizard's wording), the script stops with a clear message instead of hanging indefinitely.

## 6. Safety checks built into the script

- Checks passwords for characters that would break the `expect` block.
- Verifies the archive actually downloaded (non-empty file).
- Verifies `iRedMail.sh` exists after extraction.
- `set -euo pipefail` — the script stops immediately on any unexpected error.

## 7. After the reboot

Once the server reboots, the script prints a full summary containing:

**DNS records** (MX, SPF, DKIM, DMARC) — add these with your DNS provider.

**Let's Encrypt certificate:**

```bash
sudo snap install certbot --classic
sudo certbot certonly --webroot -w /opt/www/well_known \
  -d mail.example.com -m hello@example.com --agree-tos
```

**Required ports** (server and router/NAT):

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 | TCP | SSH |
| 25 | TCP | SMTP |
| 80 | TCP | HTTP (Let's Encrypt, redirect) |
| 443 | TCP | HTTPS (webmail, iRedAdmin) |
| 110 / 995 | TCP | POP3 / POP3S |
| 143 / 993 | TCP | IMAP / IMAPS |
| 587 | TCP | SMTP Submission |
| 465 | TCP | SMTPS |
| 4190 | TCP | ManageSieve (optional) |

If the server sits behind a home/office router, forward these ports via **Port Forwarding / NAT** to the server's local IP.

**Post-install access:**

- iRedAdmin: `https://mail.example.com/iredadmin`
- Webmail: `https://mail.example.com/mail`

## 8. Troubleshooting

- **Script stops with `TIMEOUT waiting for ... prompt`** → the wording of that wizard step changed in a newer iRedMail release. Run the installer manually instead: `sudo bash iRedMail.sh` and step through it by hand.
- **`ERROR: Download failed or file is empty`** → check that `IREDMAIL_VERSION` matches the current version on [iredmail.org/download.html](https://www.iredmail.org/download.html), and that the server has internet access.
- **Port 25 still doesn't work after forwarding it** → many providers (hosting and residential ISPs alike) block port 25 to fight spam — you'll need to request it be unblocked via a support ticket.

---

*install_iredmail.sh — prepared by dx4wrld*
