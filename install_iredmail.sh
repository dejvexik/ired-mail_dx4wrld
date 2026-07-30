#!/usr/bin/env bash
#
# install_iredmail.sh
# Automated iRedMail installation for Ubuntu 22.04
# Based on the guide "How to Install iRedMail on Ubuntu 22.04" (Vultr).
#
# Script by: dx4wrld
#
# USAGE:
# 1. Edit the variables in the "SETTINGS" section below.
# 2. Run on the server as a non-root user with sudo privileges.
# 3. Make sure port 25 is unblocked (support ticket with your provider).
# 4. Run: sudo bash install_iredmail.sh
#
# NOTE: iRedMail.sh itself is an interactive wizard by design.
# This script automates it using "expect", following the exact
# order of steps from the official guide (Nginx, MariaDB,
# default LDAP suffix, etc.). If a newer iRedMail version changes
# the order of prompts, walk through the process manually instead
# (just run: sudo bash iRedMail.sh) and answer the wizard by hand.
#
# Updated: bumped to the current latest stable release, 1.8.4
# (released 2026-07-22), and hardened the automation so it fails
# loudly instead of hanging silently if something goes wrong.

set -euo pipefail

######################################
# SETTINGS – EDIT BEFORE RUNNING     #
######################################
MAIL_HOSTNAME="mail.example.com"        # mail server FQDN
MAIN_DOMAIN="example.com"               # your domain
SERVER_IP="192.0.2.1"                   # server's public IP (for SPF)
MYSQL_ROOT_PASSWORD="ChangeThisPassword1!"
POSTMASTER_PASSWORD="ChangeThisPassword2!"
IREDMAIL_VERSION="1.8.4"                # latest stable release (iredmail.org/download.html)

######################################
# 0. root/sudo check                 #
######################################
if [[ $EUID -eq 0 ]]; then
  echo "Run this script via 'sudo bash install_iredmail.sh', not as a direct root shell."
fi

# Fail fast if any password contains characters that would break the
# Tcl/expect "send" strings below (quotes, backslashes, $ signs).
for pw in "${MYSQL_ROOT_PASSWORD}" "${POSTMASTER_PASSWORD}"; do
  if [[ "${pw}" == *'"'* || "${pw}" == *'\'* || "${pw}" == *'$'* || "${pw}" == *'['* || "${pw}" == *']'* ]]; then
    echo "ERROR: Passwords must not contain \", \\, \$, [ or ] — please change MYSQL_ROOT_PASSWORD / POSTMASTER_PASSWORD."
    exit 1
  fi
done

echo ">>> [1/9] Setting hostname to ${MAIL_HOSTNAME}"
sudo hostnamectl set-hostname "${MAIL_HOSTNAME}"

echo ">>> [2/9] Updating /etc/hosts"
if ! grep -q "${MAIL_HOSTNAME}" /etc/hosts; then
  sudo sed -i "s/^127.0.1.1.*/127.0.1.1 ${MAIL_HOSTNAME} ${MAIL_HOSTNAME%%.*}/" /etc/hosts
fi
echo "Current hostname -f: $(hostname -f)"

echo ">>> [3/9] Updating the system"
sudo apt update -y
sudo apt upgrade -y

echo ">>> [4/9] Installing 'expect' (to automate the installer)"
sudo apt install -y expect wget tar

echo ">>> [5/9] Downloading iRedMail ${IREDMAIL_VERSION}"
cd /root 2>/dev/null || cd ~
IREDMAIL_TARBALL="iRedMail-${IREDMAIL_VERSION}.tar.gz"
IREDMAIL_URL="https://github.com/iredmail/iRedMail/archive/refs/tags/${IREDMAIL_VERSION}.tar.gz"

wget -q "${IREDMAIL_URL}" -O "${IREDMAIL_TARBALL}"
if [[ ! -s "${IREDMAIL_TARBALL}" ]]; then
  echo "ERROR: Download failed or file is empty. Check IREDMAIL_VERSION (${IREDMAIL_VERSION}) and your network."
  echo "       Latest stable version is listed at: https://www.iredmail.org/download.html"
  exit 1
fi

tar -xzf "${IREDMAIL_TARBALL}"
cd "iRedMail-${IREDMAIL_VERSION}"

if [[ ! -f "iRedMail.sh" ]]; then
  echo "ERROR: iRedMail.sh not found after extraction. The release archive layout may have changed."
  exit 1
fi

echo ">>> [6/9] Running iRedMail.sh (automated responses)"
sudo expect <<EOF
# Overall safety net: if any expect prompt doesn't show up within
# 20 minutes, bail out loudly instead of hanging forever.
set timeout 1200
log_user 1

spawn bash iRedMail.sh

expect {
  "Press \"Enter\" to continue" { send "\r" } \
  timeout { puts "TIMEOUT waiting for welcome prompt"; exit 1 }
}

# default mail storage /var/vmail
expect {
  "Please specify the directory" { send "\r" } \
  timeout { puts "TIMEOUT waiting for storage path prompt"; exit 1 }
}

# Nginx as web server (default)
expect {
  "web server" { send "\r" } \
  timeout { puts "TIMEOUT waiting for web server prompt"; exit 1 }
}

# MariaDB backend - down + space
expect {
  "backend" { send "\033\[B"; send " "; send "\r" } \
  timeout { puts "TIMEOUT waiting for backend prompt"; exit 1 }
}

# LDAP suffix - default
expect {
  "suffix" { send "\r" } \
  timeout { puts "TIMEOUT waiting for LDAP suffix prompt"; exit 1 }
}

# MySQL root password
expect {
  "password for MySQL" { send "${MYSQL_ROOT_PASSWORD}\r" } \
  timeout { puts "TIMEOUT waiting for MySQL root password prompt"; exit 1 }
}
expect {
  "again" { send "${MYSQL_ROOT_PASSWORD}\r" } \
  timeout { puts "TIMEOUT waiting for MySQL root password confirmation"; exit 1 }
}

# Domain
expect {
  "domain name" { send "${MAIN_DOMAIN}\r" } \
  timeout { puts "TIMEOUT waiting for domain name prompt"; exit 1 }
}

# Password for postmaster
expect {
  "password for the domain administrator" { send "${POSTMASTER_PASSWORD}\r" } \
  timeout { puts "TIMEOUT waiting for postmaster password prompt"; exit 1 }
}
expect {
  "again" { send "${POSTMASTER_PASSWORD}\r" } \
  timeout { puts "TIMEOUT waiting for postmaster password confirmation"; exit 1 }
}

# Optional components - enter (default selection)
expect {
  "optional components" { send "\r" } \
  timeout { puts "TIMEOUT waiting for optional components prompt"; exit 1 }
}

# Confirm installation
expect {
  "Continue?" { send "y\r" } \
  timeout { puts "TIMEOUT waiting for Continue? prompt"; exit 1 }
}

# Firewall rules
expect {
  "firewall rules" { send "y\r" } \
  timeout { puts "TIMEOUT waiting for firewall rules prompt"; exit 1 }
}
expect {
  "Restart firewall now" { send "y\r" } \
  timeout { puts "TIMEOUT waiting for restart firewall prompt"; exit 1 }
}

expect eof
EOF

echo ">>> [7/9] iRedMail installation complete. Rebooting in 10 seconds..."
sleep 10
sudo systemctl reboot &

echo ">>> [8/9] After reboot, don't forget to set up the DNS records (see below)."
echo ">>> [9/9] For Let's Encrypt certificates, run this after reboot:"

cat <<NOTE
======================================================================
IMPORTANT - SET THESE DNS RECORDS WITH YOUR REGISTRAR:
======================================================================
MX  @  -> ${MAIL_HOSTNAME} (priority 10)
TXT @  -> "v=spf1 a mx ip4:${SERVER_IP} -all"
TXT dkim._domainkey -> value from: sudo amavisd-new showkeys
TXT _dmarc -> "v=DMARC1; p=reject; rua=mailto:dmarc-reports@${MAIN_DOMAIN}; pct=100"

Verify DKIM after setup:
sudo amavisd-new testkeys
======================================================================
LET'S ENCRYPT SSL (run manually after reboot):
======================================================================
sudo snap install certbot --classic
sudo certbot certonly --webroot -w /opt/www/well_known \\
  -d ${MAIL_HOSTNAME} -m hello@${MAIN_DOMAIN} --agree-tos

Then update the certificate paths in:
/etc/nginx/sites-available/00-default-ssl.conf
/etc/nginx/templates/ssl.tmpl
/etc/postfix/main.cf
/etc/dovecot/dovecot.conf

And restart the services:
sudo systemctl restart nginx postfix dovecot
======================================================================
REQUIRED FIREWALL / ROUTER PORTS:
======================================================================
TCP 22 (SSH), 25 (SMTP), 80 (HTTP), 443 (HTTPS),
110 (POP3), 995 (POP3S), 143 (IMAP), 993 (IMAPS),
587 (SMTP submission), 465 (SMTPS), 4190 (ManageSieve, optional)
If the server is behind a home/office router (NAT), forward these
ports to the server's local IP in the router's Port Forwarding /
Virtual Server settings.
======================================================================
Post-installation access:
iRedAdmin: https://${MAIL_HOSTNAME}/iredadmin
Webmail:   https://${MAIL_HOSTNAME}/mail
======================================================================
Installed version: iRedMail ${IREDMAIL_VERSION}
Script created by: dx4wrld
NOTE
