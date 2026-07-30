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
# the order of prompts, walk through the process manually instead.

set -euo pipefail

######################################
# SETTINGS – EDIT BEFORE RUNNING     #
######################################
MAIL_HOSTNAME="mail.example.com"        # mail server FQDN
MAIN_DOMAIN="example.com"               # your domain
SERVER_IP="192.0.2.1"                   # server's public IP (for SPF)
MYSQL_ROOT_PASSWORD="ChangeThisPassword1!"
POSTMASTER_PASSWORD="ChangeThisPassword2!"
IREDMAIL_VERSION="1.7.3"

######################################
# 0. root/sudo check                 #
######################################
if [[ $EUID -eq 0 ]]; then
  echo "Run this script via 'sudo bash install_iredmail.sh', not as a direct root shell."
fi

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
sudo apt install -y expect wget

echo ">>> [5/9] Downloading iRedMail ${IREDMAIL_VERSION}"
cd /root 2>/dev/null || cd ~
wget -q "https://github.com/iredmail/iRedMail/archive/refs/tags/${IREDMAIL_VERSION}.tar.gz" -O "iRedMail-${IREDMAIL_VERSION}.tar.gz"
tar -xzf "iRedMail-${IREDMAIL_VERSION}.tar.gz"
cd "iRedMail-${IREDMAIL_VERSION}"

echo ">>> [6/9] Running iRedMail.sh (automated responses)"
sudo expect <<EOF
set timeout -1
spawn bash iRedMail.sh

expect "Press \"Enter\" to continue"
send "\r"

# default mail storage /var/vmail
expect "Please specify the directory"
send "\r"

# Nginx as web server (default)
expect "web server"
send "\r"

# MariaDB backend - down + space
expect "backend"
send "\033\[B"
send " "
send "\r"

# LDAP suffix - default
expect "suffix"
send "\r"

# MySQL root password
expect "password for MySQL"
send "${MYSQL_ROOT_PASSWORD}\r"
expect "again"
send "${MYSQL_ROOT_PASSWORD}\r"

# Domain
expect "domain name"
send "${MAIN_DOMAIN}\r"

# Password for postmaster
expect "password for the domain administrator"
send "${POSTMASTER_PASSWORD}\r"
expect "again"
send "${POSTMASTER_PASSWORD}\r"

# Optional components - enter (default selection)
expect "optional components"
send "\r"

# Confirm installation
expect "Continue?"
send "y\r"

# Firewall rules
expect "firewall rules"
send "y\r"
expect "Restart firewall now"
send "y\r"

expect eof
EOF

echo ">>> [7/9] iRedMail installation complete. Rebooting in 10 seconds..."
sleep 10
sudo systemctl reboot &

echo ">>> [8/9] After reboot, don't forget to set up the DNS records (see below)."
echo ">>> [9/9] For Let's Encrypt certificates, run this after reboot:"

cat <<'NOTE'
======================================================================
IMPORTANT - SET THESE DNS RECORDS WITH YOUR REGISTRAR:
======================================================================
MX  @  -> mail.example.com (priority 10)
TXT @  -> "v=spf1 a mx ip4:SERVER_IP -all"
TXT dkim._domainkey -> value from: sudo amavisd-new showkeys
TXT _dmarc -> "v=DMARC1; p=reject; rua=mailto:dmarc-reports@yourdomain.com; pct=100"

Verify DKIM after setup:
sudo amavisd-new testkeys
======================================================================
LET'S ENCRYPT SSL (run manually after reboot):
======================================================================
sudo snap install certbot --classic
sudo certbot certonly --webroot -w /opt/www/well_known \
  -d mail.example.com -m hello@example.com --agree-tos

Then update the certificate paths in:
/etc/nginx/sites-available/00-default-ssl.conf
/etc/nginx/templates/ssl.tmpl
/etc/postfix/main.cf
/etc/dovecot/dovecot.conf

And restart the services:
sudo systemctl restart nginx postfix dovecot
======================================================================
Post-installation access:
iRedAdmin: https://mail.example.com/iredadmin
Webmail:   https://mail.example.com/mail
======================================================================
Script created by: dx4wrld
NOTE
