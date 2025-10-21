#!/bin/bash
# ============================================================
#  OctaSec | MISP 2.5 Full Installation Demo (Ubuntu 24.04)
#  Author: xantzs
# ============================================================

# Your host IP
MISP_HOST="x.x.x.x"
ADMIN_EMAIL="admin@admin.test"
ADMIN_PASSWORD="xxxxxxxxxx"  # Please change this!

echo "=== [1/10] Updating system and installing prerequisites ==="
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl unzip gnupg-agent software-properties-common apache2

# 🧱 Creating dedicated MISP user
echo "=== [2/10] Creating user misp ==="
sudo adduser misp --gecos "MISP,,," --disabled-password
echo "misp:OctaSec123!" | sudo chpasswd
sudo usermod -aG sudo,staff,www-data misp

# 🧩 Installing MISP with specific version for Ubuntu 24.04
echo "=== [3/10] Downloading and running official MISP installer ==="
sudo -i -u misp bash << 'EOF'
cd /tmp
# Try Ubuntu 22.04 installer for compatibility
wget --no-cache -O INSTALL.sh https://raw.githubusercontent.com/MISP/MISP/2.5/INSTALL/INSTALL.ubuntu2404.sh
chmod +x INSTALL.sh
# Run with core only first
sudo bash INSTALL.sh -c
EOF

# Check if MISP directory exists
if [ ! -d "/var/www/MISP" ]; then
    echo "❌ MISP installation failed, trying alternative method..."
    # Alternative installation
    sudo -i -u misp bash << 'EOF'
    cd /var/www
    sudo git clone https://github.com/MISP/MISP.git
    cd MISP
    git checkout 2.5
    sudo bash INSTALL/INSTALL.sh -c
EOF
fi

# 🌐 Configuring BaseURL with your IP only (no domain)
echo "=== [4/10] Configuring BaseURL with IP address ==="
if [ -d "/var/www/MISP" ]; then
    sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting MISP.baseurl "https://$MISP_HOST"
else
    echo "❌ MISP directory not found, skipping configuration"
fi

# 🔧 Configure Apache
echo "=== [4.5/10] Configuring Apache ==="
# Check if Apache is installed and running
if ! systemctl is-active --quiet apache2; then
    echo "Starting Apache2 service..."
    sudo systemctl start apache2
    sudo systemctl enable apache2
fi

# Configure Apache for MISP if config files exist
if [ -f "/etc/apache2/sites-available/misp.conf" ]; then
    sudo sed -i "s/ServerName localhost/ServerName $MISP_HOST/g" /etc/apache2/sites-available/misp.conf
fi

if [ -f "/etc/apache2/sites-available/misp-ssl.conf" ]; then
    sudo sed -i "s/ServerName localhost/ServerName $MISP_HOST/g" /etc/apache2/sites-available/misp-ssl.conf
fi

# Remove any domain entries from hosts file to ensure IP access
sudo sed -i '/misp.local/d' /etc/hosts

# 🧩 Enabling SSL
echo "=== [5/10] Enabling Apache SSL ==="
sudo a2enmod ssl
sudo a2ensite default-ssl 2>/dev/null || true

# Enable MISP sites if they exist
if [ -f "/etc/apache2/sites-available/misp-ssl.conf" ]; then
    sudo a2ensite misp-ssl.conf 2>/dev/null || true
elif [ -f "/etc/apache2/sites-available/misp.conf" ]; then
    sudo a2ensite misp.conf 2>/dev/null || true
fi

sudo systemctl reload apache2

# 🔐 Password policy adjustment
echo "=== [6/10] Adjusting password policy for demo ==="
if [ -d "/var/www/MISP" ]; then
    sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Security.password_policy_length" 8
    sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Security.password_policy_complexity" "^(?=.{8,}).*$"
else
    echo "❌ MISP directory not found, skipping password policy configuration"
fi

# 🔑 Reset admin password
echo "=== [7/10] Resetting admin password ==="
if [ -d "/var/www/MISP" ]; then
    sudo -u www-data /var/www/MISP/app/Console/cake user list
    sudo -u www-data /var/www/MISP/app/Console/cake Password "$ADMIN_EMAIL" "$ADMIN_PASSWORD"
else
    echo "❌ MISP directory not found, skipping password reset"
fi

# 📡 Loading feeds
echo "=== [8/10] Enabling default feeds ==="
if [ -d "/var/www/MISP" ]; then
    sudo -u www-data /var/www/MISP/app/Console/cake Server cacheFeed 1
    sudo -u www-data /var/www/MISP/app/Console/cake Server fetchFeed 1
else
    echo "❌ MISP directory not found, skipping feed configuration"
fi

# 📊 Installing Dashboard (optional)
echo "=== [9/10] Installing MISP Dashboard (optional) ==="
sudo apt install -y redis-server python3-venv python3-pip
cd /var/www
sudo git clone https://github.com/MISP/misp-dashboard.git
sudo chown -R www-data:www-data misp-dashboard
cd misp-dashboard
python3 -m venv venv
./venv/bin/pip install -U pip wheel
./venv/bin/pip install -r requirements.txt

sudo tee /etc/systemd/system/misp-dashboard.service >/dev/null <<'UNIT'
[Unit]
Description=MISP Dashboard
After=network.target redis-server.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/misp-dashboard
ExecStart=/var/www/misp-dashboard/venv/bin/python3 /var/www/misp-dashboard/app.py
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now misp-dashboard

# 🧠 Restarting services
echo "=== [10/10] Restarting services ==="
sudo systemctl restart apache2 2>/dev/null || echo "⚠️  Apache2 restart failed, but continuing..."
sudo systemctl restart redis-server 2>/dev/null || echo "⚠️  Redis restart failed, but continuing..."
sudo systemctl restart misp-dashboard 2>/dev/null || echo "⚠️  MISP Dashboard restart failed, but continuing..."

# ✅ Summary
echo "=============================================================="
echo "✅ MISP installation complete!"
echo "🌐 Access: https://$MISP_HOST"
echo "👤 Username: $ADMIN_EMAIL"
echo "🔑 Password: $ADMIN_PASSWORD"
echo "=============================================================="
echo "⚠️  TROUBLESHOOTING NOTES:"
echo "⚠️  1. If Apache failed to install, run: sudo apt install apache2"
echo "⚠️  2. Check MISP status: sudo -u www-data /var/www/MISP/app/Console/cake Admin getSetting MISP.baseurl"
echo "⚠️  3. Check Apache status: sudo systemctl status apache2"
echo "⚠️  4. Check logs: sudo tail -f /var/log/apache2/error.log"
echo "=============================================================="
