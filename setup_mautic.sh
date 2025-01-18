#!/bin/bash

###-----------------------------------###
### Fully Automatic Mautic 5.2.1 Installer ###
###-----------------------------------###
#
# This script installs Mautic 5.2.1 on Ubuntu 24.04 in an AWS EC2 instance.
# It configures Apache 2, PHP 8.2, MariaDB 11.4, Snap, Certbot, and enables SSL.
#
# Optimized for a clean and secure setup.

### Variables ###
MAUTIC_DOMAIN=""  # Domain for the Mautic instance
CERTBOT_EMAIL=""  # Email for Let's Encrypt notifications

MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)  # Secure root password
MYSQL_MAUTIC_USER="mautic_user"
MYSQL_MAUTIC_PASSWORD=$(openssl rand -base64 32)  # Secure Mautic user password

MAUTIC_ADMIN_USER="admin"  # Default Mautic admin username
MAUTIC_ADMIN_PASSWORD=$(openssl rand -base64 16)  # Secure admin password

MAUTIC_VERSION="5.2.1"
PHP_VERSION="8.2"
MARIADB_VERSION="11.4"

TIMEZONE="UTC"  # Default timezone, can be customized

### Helper Functions ###
function pause_for_credentials {
    echo "\nGenerated credentials:"
    echo "MySQL Root User: root"
    echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
    echo "Mautic Database User: $MYSQL_MAUTIC_USER"
    echo "Mautic Database Password: $MYSQL_MAUTIC_PASSWORD"
    echo "Mautic Admin User: $MAUTIC_ADMIN_USER"
    echo "Mautic Admin Password: $MAUTIC_ADMIN_PASSWORD"
    echo "\nPlease save these credentials securely before continuing."
    read -p "Press ENTER to continue..."
}

function check_requirements {
    echo "\nChecking server requirements..."

    REQUIRED_DISK_SPACE=20  # GB
    REQUIRED_RAM=2  # GB
    REQUIRED_VCPUS=2

    echo "Checking disk space..."
    FREE_DISK=$(df --output=avail -m / | tail -1)
    GB_DISK=$((FREE_DISK/1000))
    if [ $GB_DISK -lt $REQUIRED_DISK_SPACE ]; then
        echo "Warning: At least $REQUIRED_DISK_SPACE GB of free disk space is recommended."
        read -p "Do you want to continue anyway? (y/N): " CONTINUE_DISK
        if [[ ! $CONTINUE_DISK =~ ^[Yy]$ ]]; then
            echo "Exiting installation."
            exit 1
        fi
    fi

    echo "Checking CPU threads..."
    VCPUS=$(nproc)
    if [ $VCPUS -lt $REQUIRED_VCPUS ]; then
        echo "Warning: At least $REQUIRED_VCPUS vCPUs are recommended."
        read -p "Do you want to continue anyway? (y/N): " CONTINUE_CPU
        if [[ ! $CONTINUE_CPU =~ ^[Yy]$ ]]; then
            echo "Exiting installation."
            exit 1
        fi
    fi

    echo "Checking RAM..."
    ALL_RAM=$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024000)))
    if [ $ALL_RAM -lt $REQUIRED_RAM ]; then
        echo "Warning: At least $REQUIRED_RAM GB of RAM is recommended."
        read -p "Do you want to continue anyway? (y/N): " CONTINUE_RAM
        if [[ ! $CONTINUE_RAM =~ ^[Yy]$ ]]; then
            echo "Exiting installation."
            exit 1
        fi
    fi

    echo "All checks completed.\n"
}

function configure_apache {
    echo "Configuring Apache..."

    # Create Virtual Host Configuration
    cat <<EOF > /etc/apache2/sites-available/mautic.conf
<VirtualHost *:80>
    ServerName $MAUTIC_DOMAIN
    ServerAlias www.$MAUTIC_DOMAIN
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/mautic_error.log
    CustomLog \${APACHE_LOG_DIR}/mautic_access.log combined

    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L]
</VirtualHost>
EOF

    a2ensite mautic.conf
    a2enmod rewrite
    systemctl reload apache2
}

function install_dependencies {
    echo "Updating and installing dependencies..."

    apt update && apt upgrade -y
    apt install -y software-properties-common curl unzip apache2 mariadb-server \
                   php$PHP_VERSION php$PHP_VERSION-{bcmath,curl,gd,mbstring,mysql,xml,zip,cli,intl,soap} \
                   certbot python3-certbot-apache netdata

    # Enable Netdata
    systemctl start netdata
    systemctl enable netdata

    LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php -y
    curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --mariadb-server-version=$MARIADB_VERSION
    apt update && apt install -y mariadb-server
}

function configure_mariadb {
    echo "Configuring MariaDB..."

    mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
    mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE mautic CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
    mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$MYSQL_MAUTIC_USER'@'localhost' IDENTIFIED BY '$MYSQL_MAUTIC_PASSWORD';"
    mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON mautic.* TO '$MYSQL_MAUTIC_USER'@'localhost';"
    mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"
}

function install_mautic {
    echo "Installing Mautic..."

    wget -q https://github.com/mautic/mautic/releases/download/$MAUTIC_VERSION/$MAUTIC_VERSION.zip
    unzip -q $MAUTIC_VERSION.zip -d /var/www/html
    rm $MAUTIC_VERSION.zip
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html

    # Create default admin user
    sudo -u www-data php /var/www/html/bin/console mautic:admin:create \
        --username=$MAUTIC_ADMIN_USER \
        --password=$MAUTIC_ADMIN_PASSWORD \
        --email=$CERTBOT_EMAIL
}

function setup_ssl {
    echo "Setting up SSL with Certbot..."

    certbot --apache -d $MAUTIC_DOMAIN -d www.$MAUTIC_DOMAIN --non-interactive --agree-tos --email $CERTBOT_EMAIL --no-redirect
}

function configure_timezone {
    echo "Configuring server timezone..."
    timedatectl set-timezone $TIMEZONE
}

function configure_firewall {
    echo "Configuring UFW firewall..."
    apt install ufw -y
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw enable
}

function setup_cron_jobs {
    echo "Setting up cron jobs for database backups..."

    # Backup database daily and keep last 7 backups
    mkdir -p /var/backups/mautic_db
    echo "0 2 * * * root mysqldump -u root -p$MYSQL_ROOT_PASSWORD mautic > /var/backups/mautic_db/mautic_\$(date +\%F).sql && find /var/backups/mautic_db -type f -mtime +7 -exec rm {} \;" > /etc/cron.d/mautic-backups
    chmod 644 /etc/cron.d/mautic-backups
    systemctl restart cron
}

function display_post_installation_notes {
    echo "\nMautic installation is complete! Here are the details:"
    echo "URL: https://$MAUTIC_DOMAIN"
    echo "Admin Username: $MAUTIC_ADMIN_USER"
    echo "Admin Password: $MAUTIC_ADMIN_PASSWORD"
    echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
    echo "Mautic Database Username: $MYSQL_MAUTIC_USER"
    echo "Mautic Database Password: $MYSQL_MAUTIC_PASSWORD"
    echo "\nMonitoring enabled with Netdata. Access it at http://<server-ip>:19999"
    echo "\nPlease save these details securely."
}

### Main Execution ###
pause_for_credentials
check_requirements
install_dependencies
configure_apache
configure_mariadb
install_mautic
setup_ssl
configure_timezone
configure_firewall
setup_cron_jobs
display_post_installation_notes

echo "\nMautic setup is complete!"
