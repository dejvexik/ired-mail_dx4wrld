# install_iredmail.sh — Automated iRedMail Installer (Ubuntu 22.04)

![iRedMail Fast Install by dx4wrld](https://cdn.discordapp.com/attachments/1532368721174073498/1532369265041084457/content.png?ex=6a6c9996&is=6a6b4816&hm=26deb4607b34962679b5155992595a9aa46fa8a59e18a0883b299d203f99e3a9)

**Automated deployment script**
A complete, detailed reference for `install_iredmail.sh` — what it does, why it does it that way, how to configure it, how to run it, and how to troubleshoot it. Installs the current stable release of iRedMail (**1.8.4**) on a fresh Ubuntu 22.04 server.

*Compiled & automated by dx4wrld · Fast Run*

---

## Contents

1. [Overview](#1-overview)
2. [What the script does, in detail](#2-what-the-script-does-in-detail)
3. [Requirements](#3-requirements)
4. [Configuring the variables](#4-configuring-the-variables)
5. [Running the script](#5-running-the-script)
6. [Installation walkthrough, step by step](#6-installation-walkthrough-step-by-step)
7. [How the `expect` automation actually works](#7-how-the-expect-automation-actually-works)
8. [Safety checks built into the script](#8-safety-checks-built-into-the-script)
9. [After the reboot — DNS records explained](#9-after-the-reboot--dns-records-explained)
10. [Let's Encrypt SSL setup](#10-lets-encrypt-ssl-setup)
11. [Required ports, explained one by one](#11-required-ports-explained-one-by-one)
12. [Port forwarding on a home/office router](#12-port-forwarding-on-a-homeoffice-router)
13. [Post-installation testing checklist](#13-post-installation-testing-checklist)
14. [Troubleshooting](#14-troubleshooting)
15. [Maintenance and updates](#15-maintenance-and-updates)
16. [Basic security hardening after install](#16-basic-security-hardening-after-install)
17. [FAQ](#17-faq)

---

## 1. Overview

`install_iredmail.sh` is a wrapper around the official iRedMail installer (`iRedMail.sh`) that removes the manual, interactive part of the process. iRedMail itself ships as a text-based wizard: you run a shell script, and it asks you a series of questions (storage path, web server, database backend, domain, passwords, and so on).

That's fine for a one-off install, but it's tedious to repeat, easy to mistype a password into, and impossible to script into a larger automation pipeline (Ansible, Terraform provisioning, CI, etc.) without extra tooling. This script solves that by using **`expect`**, a Tcl-based tool built specifically for automating interactive command-line programs: it "expects" a certain string of text to appear in the program's output, and when it does, it "sends" a predetermined response, exactly as if a human had typed it and pressed Enter.

The result is a single command — `sudo bash install_iredmail.sh` — that takes a bare Ubuntu 22.04 server all the way to a fully functional mail server with Postfix, Dovecot, Nginx, MariaDB, Roundcube webmail, and iRedAdmin, then reboots it and prints out everything you still need to do manually (DNS, TLS certificates).

---

## 2. What the script does, in detail

Reading top to bottom, the script performs these actions:

1. **Hostname configuration** — sets the machine's hostname to your mail server's fully qualified domain name (FQDN), e.g. `mail.example.com`. This matters because Postfix and other mail components identify themselves to the outside world using the system hostname, and a mismatch between hostname, DNS, and the certificate name is one of the most common causes of mail servers landing in spam folders.
2. **`/etc/hosts` update** — adds a `127.0.1.1` line mapping the FQDN to the loopback address, so that local processes can resolve the server's own name without depending on external DNS.
3. **System update** — runs `apt update` and `apt upgrade` so the installer works against a fully patched base system.
4. **Dependency installation** — installs `expect`, `wget`, and `tar`, the three tools the rest of the script depends on.
5. **Download and extraction** — downloads the iRedMail 1.8.4 source tarball directly from the official GitHub repository (`github.com/iredmail/iRedMail`), verifies the download actually produced a non-empty file, extracts it, and confirms `iRedMail.sh` is present before continuing.
6. **Automated wizard run** — launches `iRedMail.sh` under `expect` and answers every prompt automatically (web server, database backend, LDAP suffix, MySQL root password, domain name, mailbox administrator password, optional components, final confirmation, and firewall rules).
7. **Reboot** — iRedMail's own documentation recommends a reboot after installation to make sure every service (Postfix, Dovecot, Nginx, MariaDB, Amavis, ClamAV, SpamAssassin) starts cleanly with the new configuration. The script waits 10 seconds and then triggers `sudo systemctl reboot` in the background so the final summary can still print to your terminal before the connection drops.
8. **Post-install summary** — prints the DNS records you need to create, the exact `certbot` command for a Let's Encrypt certificate, the full list of ports that must be reachable, and the URLs for iRedAdmin and Roundcube.

---

## 3. Requirements

| Requirement | Detail |
|---|---|
| Operating system | Ubuntu **22.04 LTS**, fresh install (iRedMail should be installed on a clean system — it takes over Postfix, Dovecot, Nginx/Apache and MariaDB/PostgreSQL configuration) |
| RAM | Minimum **4 GB** — less than that and ClamAV (the antivirus engine) will struggle or fail to start |
| Disk | At least 20 GB free is a safe minimum for OS + mail components + mailbox storage headroom |
| User | A **non-root** user with `sudo` privileges (the script itself checks `$EUID` and warns if you're already root) |
| DNS | At least two **A records** already pointing at the server's public IP: one for the domain itself (`example.com`) and one for the mail subdomain (`mail.example.com`) |
| ISP / hosting provider | Outbound/inbound **port 25 unblocked** — most cloud and hosting providers block this by default for anti-spam reasons and require a support ticket to open it |
| Network access | Server must be able to reach `github.com` (to download the tarball) and the Ubuntu package repositories |
| Firewall / router | See [section 11](#11-required-ports-explained-one-by-one) and [section 12](#12-port-forwarding-on-a-homeoffice-router) |

---

## 4. Configuring the variables

Open `install_iredmail.sh` and edit the `SETTINGS` block near the top before running anything:

```bash
MAIL_HOSTNAME="mail.example.com"        # mail server FQDN
MAIN_DOMAIN="example.com"               # your domain
SERVER_IP="192.0.2.1"                   # server's public IP (for SPF)
MYSQL_ROOT_PASSWORD="ChangeThisPassword1!"
POSTMASTER_PASSWORD="ChangeThisPassword2!"
IREDMAIL_VERSION="1.8.4"                # current stable release
```

| Variable | Purpose | Notes |
|---|---|---|
| `MAIL_HOSTNAME` | The FQDN the server will identify itself as | Must match a DNS A record you control |
| `MAIN_DOMAIN` | The domain iRedMail will create as the first mail domain during setup | This is the part after the `@` in your future mailboxes, e.g. `user@example.com` |
| `SERVER_IP` | The server's public IPv4 address | Used only for building the SPF record text printed at the end — it is **not** used to configure networking |
| `MYSQL_ROOT_PASSWORD` | Password for the MariaDB `root` user | Used once during setup; store it somewhere safe afterward |
| `POSTMASTER_PASSWORD` | Password for the `postmaster@yourdomain` mailbox, which iRedMail creates as the domain administrator account | This is the account you'll use to log into iRedAdmin the first time |
| `IREDMAIL_VERSION` | Which release tag to download from GitHub | Check [iredmail.org/download.html](https://www.iredmail.org/download.html) for the current stable version before running |

**Password rules:** the script rejects passwords containing `"`, `\`, `$`, `[`, or `]`, because those characters have special meaning inside the Tcl/`expect` script that types them for you and would either break the syntax or send the wrong text to the wizard. Stick to letters, digits, and symbols like `!`, `@`, `#`, `%`, `^`, `&`, `*`, `-`, `_`, `+`, `=`.

---

## 5. Running the script

```bash
sudo bash install_iredmail.sh
```

- Must be run with `sudo` (or as root), since it configures system services, installs packages, and modifies `/etc/hosts`.
- Runs **fully unattended** from start to finish — there is nothing to click through or type once it starts.
- Typical runtime is **10–20 minutes**, dominated by package downloads (Postfix, Dovecot, MariaDB, Nginx, Roundcube, ClamAV virus definitions, etc.) and depends heavily on your server's CPU, disk, and network speed.
- Keep the terminal session open until you see the final `NOTE` summary block — closing it early (e.g. an SSH client that times out) can interrupt the `expect` automation mid-wizard.
- If you're running this over SSH on an unstable connection, consider wrapping the whole command in `tmux` or `screen` so the process survives a dropped connection:

```bash
tmux new -s iredmail
sudo bash install_iredmail.sh
# if disconnected, reconnect and run: tmux attach -t iredmail
```

---

## 6. Installation walkthrough, step by step

| Step | What happens | Approximate time |
|---|---|---|
| 1/9 | Set the hostname | instant |
| 2/9 | Update `/etc/hosts` | instant |
| 3/9 | `apt update` + `apt upgrade` | 1–5 min |
| 4/9 | Install `expect`, `wget`, `tar` | <1 min |
| 5/9 | Download and extract iRedMail 1.8.4, verify archive integrity | <1 min |
| 6/9 | Automated `iRedMail.sh` run via `expect` | 8–15 min |
| 7/9 | Reboot the server | ~1 min downtime |
| 8/9 | Reminder to set up DNS records | instant (printed text) |
| 9/9 | Print Let's Encrypt instructions and required ports | instant (printed text) |

---

## 7. How the `expect` automation actually works

Each prompt in the iRedMail wizard is handled by a block like this inside the script:

```tcl
expect {
  "password for MySQL" { send "${MYSQL_ROOT_PASSWORD}\r" } \
  timeout { puts "TIMEOUT waiting for MySQL root password prompt"; exit 1 }
}
```

- `expect { "text" { ... } timeout { ... } }` tells `expect` to watch the wizard's output for the string `"password for MySQL"`.
- As soon as that string appears, it sends the value of `MYSQL_ROOT_PASSWORD` followed by `\r` (a carriage return, equivalent to pressing Enter).
- If that string does **not** appear within the configured timeout window (`set timeout 1200`, i.e. 20 minutes), the `timeout` branch fires instead: it prints a clear diagnostic message and exits with a non-zero status, which — combined with `set -euo pipefail` in the outer bash script — stops the whole script immediately instead of leaving it hanging forever.

The full sequence of prompts handled, in order, is:

1. Welcome screen → press Enter
2. Mail storage directory → press Enter (accepts the default, `/var/vmail`)
3. Web server selection → press Enter (accepts the default, Nginx)
4. Backend selection (LDAP/MySQL/PostgreSQL) → sends a down-arrow + space to select **MariaDB**, then Enter
5. LDAP suffix → press Enter (accepts the domain-based default — only relevant if you'd chosen an LDAP backend, harmless to answer here either way)
6. MySQL root password → sent twice (initial entry + confirmation)
7. First mail domain name → sent from `MAIN_DOMAIN`
8. Postmaster/domain administrator password → sent twice (initial entry + confirmation)
9. Optional components selection → press Enter (accepts the pre-selected defaults, which normally include SpamAssassin, ClamAV, Amavis, Fail2ban, and Roundcube)
10. Final "Continue?" confirmation → sends `y`
11. "Configure firewall rules?" → sends `y`
12. "Restart firewall now?" → sends `y`

> If a future iRedMail release rewords one of these prompts, only that single `expect` block needs to be updated — locate the corresponding string and adjust it to match the new wizard text.

---

## 8. Safety checks built into the script

- **Password sanitation** — rejects any password containing `"`, `\`, `$`, `[`, or `]` before the `expect` block is even generated, avoiding silent corruption of the automated input.
- **Download verification** — after `wget`, the script checks that the tarball exists and is non-empty (`[[ -s "$IREDMAIL_TARBALL" ]]`) before attempting to extract it.
- **Extraction verification** — after `tar -xzf`, the script checks that `iRedMail.sh` actually exists in the extracted directory before trying to run it.
- **Per-prompt timeouts** — every single `expect` block has its own 20-minute timeout with a descriptive error message, rather than one giant catch-all timeout at the end.
- **`set -euo pipefail`** — standard Bash safety net: the script exits immediately on any unhandled error (`-e`), on use of an undefined variable (`-u`), and propagates failure through pipelines (`-o pipefail`) instead of silently ignoring a failed command in the middle of a pipe.

---

## 9. After the reboot — DNS records explained

Once the server comes back up, add the following records with your DNS provider (registrar or DNS host, e.g. Cloudflare, Route 53, etc.):

| Type | Name | Value | What it's for |
|---|---|---|---|
| **MX** | `@` | `mail.example.com`, priority `10` | Tells other mail servers where to deliver mail for your domain |
| **TXT (SPF)** | `@` | `"v=spf1 a mx ip4:SERVER_IP -all"` | Declares which servers are allowed to send mail *as* your domain; the `-all` means "reject everything else" — this is one of the biggest factors in whether your outgoing mail lands in inboxes or spam folders |
| **TXT (DKIM)** | `dkim._domainkey` | output of `sudo amavisd-new showkeys` | A public key that lets receiving servers cryptographically verify that mail claiming to be from you was actually signed by your server and hasn't been tampered with |
| **TXT (DMARC)** | `_dmarc` | `"v=DMARC1; p=reject; rua=mailto:dmarc-reports@example.com; pct=100"` | Tells receiving servers what to do with mail that fails SPF/DKIM checks (`p=reject` = discard it), and where to send aggregate reports about your domain's mail authentication |

After adding the DKIM record, verify it propagated correctly:

```bash
sudo amavisd-new testkeys
# Expected output: dkim._domainkey.example.com => pass
```

DNS propagation can take anywhere from a few minutes to a few hours depending on your provider's TTL settings — don't panic if `testkeys` doesn't pass immediately.

---

## 10. Let's Encrypt SSL setup

The script prints these commands as a reminder; they are **not** run automatically because they require DNS to already be pointing at the server and port 80 to be reachable from the internet (for the HTTP-01 challenge):

```bash
sudo snap install certbot --classic
sudo certbot certonly --webroot -w /opt/www/well_known \
  -d mail.example.com -m hello@example.com --agree-tos
```

After the certificate is issued, point the mail and web services at it by editing:

- `/etc/nginx/sites-available/00-default-ssl.conf`
- `/etc/nginx/templates/ssl.tmpl`
- `/etc/postfix/main.cf`
- `/etc/dovecot/dovecot.conf`

replacing the self-signed certificate paths iRedMail generated during install with the new `/etc/letsencrypt/live/mail.example.com/fullchain.pem` and `privkey.pem` paths, then restart the affected services:

```bash
sudo systemctl restart nginx postfix dovecot
```

Let's Encrypt certificates expire every 90 days; `certbot` installs a systemd timer or cron job by default to renew them automatically — verify with:

```bash
sudo certbot renew --dry-run
```

---

## 11. Required ports, explained one by one

| Port | Protocol | Purpose | Encrypted? |
|---|---|---|---|
| 22 | TCP | SSH — remote server administration | Yes (SSH itself) |
| 25 | TCP | SMTP — server-to-server mail transfer (receiving mail from the internet, and relaying outgoing mail to other servers) | Optional (STARTTLS) |
| 80 | TCP | HTTP — used for the Let's Encrypt HTTP-01 challenge and to redirect browsers to HTTPS | No |
| 443 | TCP | HTTPS — Roundcube webmail and iRedAdmin | Yes |
| 110 | TCP | POP3 — legacy mail retrieval, unencrypted | No (avoid unless needed for legacy clients) |
| 995 | TCP | POP3S — POP3 over implicit TLS | Yes |
| 143 | TCP | IMAP — mail retrieval, unencrypted | No (avoid unless needed for legacy clients) |
| 993 | TCP | IMAPS — IMAP over implicit TLS, the standard modern choice | Yes |
| 587 | TCP | SMTP Submission — the port mail clients use to *send* outgoing mail via STARTTLS authentication | Yes (STARTTLS) |
| 465 | TCP | SMTPS — SMTP submission over implicit TLS, increasingly the preferred alternative to 587 | Yes |
| 4190 | TCP | ManageSieve — lets mail clients manage server-side Sieve filtering rules (optional, only needed if you use Sieve filters) | Yes |

**Recommendation:** for a modern setup, expose 25, 80, 443, 587, 465, 993, and 995 publicly; leave 110 and 143 closed unless a specific legacy client genuinely requires unencrypted access.

Open them on the server's own firewall (`ufw`) if not already handled automatically by the iRedMail installer:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 25/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 587/tcp
sudo ufw allow 465/tcp
sudo ufw allow 993/tcp
sudo ufw allow 995/tcp
sudo ufw allow 4190/tcp
sudo ufw status verbose
```

---

## 12. Port forwarding on a home/office router

If the server is not directly on a public IP (i.e. it sits behind a home or office router doing NAT), you must forward the ports above from the router to the server's local IP:

1. Give the server a **static local IP** (via a DHCP reservation in the router, or a static config on the server itself) so the forwarding rules don't break after a reboot.
2. Log into the router's admin interface (commonly `192.168.0.1` or `192.168.1.1`).
3. Find the **Port Forwarding** / **NAT** / **Virtual Server** section (naming varies by vendor).
4. Create a rule for each port, forwarding external → internal on the same port number and protocol (TCP), e.g.:

   | External port | Internal IP | Internal port | Protocol |
   |---|---|---|---|
   | 25 | 192.168.1.100 | 25 | TCP |
   | 80 | 192.168.1.100 | 80 | TCP |
   | 443 | 192.168.1.100 | 443 | TCP |
   | 587 | 192.168.1.100 | 587 | TCP |
   | 465 | 192.168.1.100 | 465 | TCP |
   | 993 | 192.168.1.100 | 993 | TCP |
   | 995 | 192.168.1.100 | 995 | TCP |

5. Save and reboot the router if required.
6. Test from **outside** your local network (e.g. mobile data, or an online port-checking tool) that the ports actually respond:

```bash
   nc -zv mail.example.com 25
   nc -zv mail.example.com 443
   nc -zv mail.example.com 587
```

> Residential ISPs frequently block port 25 outright regardless of router configuration — if forwarding is correct but the port still doesn't respond externally, contact your ISP.

---

## 13. Post-installation testing checklist

Once DNS, TLS, and ports are all in place, verify the whole stack end to end:

1. **Log into iRedAdmin** at `https://mail.example.com/iredadmin` as `postmaster@example.com`.
2. **Create a test mailbox** via *Add → User*.
3. **Log into Roundcube** at `https://mail.example.com/mail` with the new mailbox.
4. **Send a test email** between `postmaster@example.com` and the new mailbox.
5. **Inspect the message headers** of a received email (in most webmail clients: *More → Show source*) and confirm:
   - `dkim=pass`
   - `spf=pass`
   - `dmarc=pass`
6. **Send yourself a test message from an external address** (e.g. Gmail/Outlook) to confirm inbound mail delivery works.
7. **Send a message to an external address** and check it doesn't land in spam; tools like [mail-tester.com](https://www.mail-tester.com) give a detailed deliverability score and flag any missing SPF/DKIM/DMARC/PTR configuration.
8. **Check your server's IP against common blacklists** (e.g. via mxtoolbox.com) — a fresh IP can sometimes already be listed from a previous tenant on cloud hosting.
9. **Verify a reverse DNS (PTR) record** exists for your server's IP pointing back to `mail.example.com` — most hosting providers let you set this in their control panel, and many receiving servers reject mail from IPs without one.

---

## 14. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Script stops with `TIMEOUT waiting for ... prompt` | The wording of that wizard step changed in a newer iRedMail release | Run the installer manually: `sudo bash iRedMail.sh` and answer that step (and any others) by hand |
| `ERROR: Download failed or file is empty` | `IREDMAIL_VERSION` doesn't match an existing GitHub tag, or no internet access | Check [iredmail.org/download.html](https://www.iredmail.org/download.html) for the current version string, and confirm the server can reach `github.com` |
| `ERROR: iRedMail.sh not found after extraction` | GitHub's archive folder-naming convention changed, or the download was corrupted | Manually `wget`/`tar` the release and inspect the resulting directory name |
| Password validation error at startup | A password contains `"`, `\`, `$`, `[`, or `]` | Change `MYSQL_ROOT_PASSWORD` / `POSTMASTER_PASSWORD` to avoid those characters |
| Mail sent externally lands in spam | Missing/incorrect SPF, DKIM, or DMARC, missing PTR record, or a blacklisted IP | Work through [section 13](#13-post-installation-testing-checklist) systematically |
| Port 25 unreachable from outside even after firewall/router config | ISP or hosting provider blocking it at the network level | Open a support ticket with your provider requesting it be unblocked |
| `amavisd-new testkeys` doesn't show `pass` | DNS hasn't propagated yet, or the TXT record was entered incorrectly (line breaks, missing quotes) | Wait for propagation (check with `dig TXT dkim._domainkey.example.com`), and double-check the exact value from `amavisd-new showkeys` was copied verbatim |
| Can't log into iRedAdmin after reboot | Services didn't start cleanly, or the postmaster password wasn't set as expected | `sudo systemctl status nginx postfix dovecot mariadb`, check logs under `/var/log/`, and confirm the domain/password entered during install matches what you're typing |
| Roundcube shows a blank page or 500 error | PHP-FPM or Nginx misconfiguration, often after manually editing SSL paths | Check `sudo tail -f /var/log/nginx/error.log` and `/opt/www/roundcubemail/logs/errors.log` |

---

## 15. Maintenance and updates

- iRedMail publishes upgrade tutorials for every version bump (e.g. "Upgrade iRedMail from 1.7.4 to 1.8.0") at [docs.iredmail.org](https://docs.iredmail.org/iredmail.releases.html) — always follow the specific tutorial for your current → target version rather than re-running the installer.
- Keep Ubuntu itself patched independently of iRedMail:

```bash
  sudo apt update && sudo apt upgrade -y
```

- Roundcube, SOGo (if installed), and netdata each have their own separate upgrade tutorials linked from the same release notes page, since they're not fully managed by the core iRedMail installer.
- iRedMail records its installed version in `/etc/iredmail-release` — check it any time with:

```bash
  cat /etc/iredmail-release
```

---

## 16. Basic security hardening after install

iRedMail installs a reasonable security baseline out of the box (Fail2ban, ClamAV, SpamAssassin, firewall rules), but a few extra steps are worth doing on any internet-facing mail server:

- **Disable password authentication over SSH** in favor of SSH keys, and consider moving SSH off port 22 if you're frequently targeted by scanners.
- **Review Fail2ban jails** (`/etc/fail2ban/jail.local`) to make sure Postfix, Dovecot, and Roundcube brute-force protection is active.
- **Set strong, unique passwords** for every mailbox — a compromised mailbox on an open-relay-adjacent mail server is a common way spammers hijack legitimate domains.
- **Enable two-factor authentication in Roundcube/iRedAdmin** if your version supports it via a plugin.
- **Regularly review `/var/log/mail.log`** for unusual send volume or authentication failures.
- **Keep DMARC at `p=reject` only after confirming SPF/DKIM pass reliably** — starting with `p=none` while monitoring DMARC aggregate reports is safer for a brand-new domain.

---

## 17. FAQ

**Can I run this on a version of Ubuntu other than 22.04?**
The script is written and tested for Ubuntu 22.04 specifically. iRedMail 1.8.4 also supports Ubuntu 24.04 and 26.04 — if you use a different release, adjust package names if needed and expect some `expect` prompts to potentially differ.

**Do I need LDAP?**
No — the script automatically selects **MariaDB** as the backend, which is the simpler and more common choice for small-to-medium deployments. LDAP is only worth the added complexity if you're integrating with an existing directory service.

**Can I re-run the script if something fails halfway through?**
Not safely as-is — iRedMail's installer isn't designed to be re-run against a partially configured system. If it fails partway through the wizard, it's generally safer to start from a fresh OS snapshot/reinstall rather than trying to resume.

**Is the MySQL root password stored anywhere after install?**
Only where you put it — in the `SETTINGS` section of this script, and wherever iRedMail's own configuration stores it (`/etc/postfix/`, `/etc/dovecot/`, etc., not in plaintext logs). Treat the script file itself as sensitive once you've filled in real passwords, and consider deleting or securing it after installation completes.

---

*install_iredmail.sh — prepared by dx4wrld*
