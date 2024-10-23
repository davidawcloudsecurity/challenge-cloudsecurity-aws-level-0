#!/bin/bash

# Variables
db_name="wp_$(date +%s)"
db_user=$db_name
db_password=$(date | md5sum | cut -c 1-12)
mysql_root_password=$(date | md5sum | cut -c 1-12)
admin_user="admin"
# Change this to a secure password
admin_password="P@ssw0rd123!" 
# Change this to a valid email
admin_email="admin@example.com"   

# Fetch the public IP address of the EC2 instance
public_ip=$(curl ifconfig.me)

# Update and install necessary packages
apt update -y
# apt upgrade -y

# Install Apache
apt install -y apache2
systemctl enable apache2
systemctl start apache2

# Change Apache to run on port 3000
sed -i 's/80/3000/g' /etc/apache2/ports.conf

# Create Apache Virtual Host for WordPress
cat <<EOF > /etc/apache2/sites-available/wordpress.conf
<VirtualHost *:3000>
    DocumentRoot /var/www/html/wordpress
    <Directory /var/www/html/wordpress>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    # Logging
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined    
</VirtualHost>
EOF

# Enable the new site configuration and disable the default one
a2ensite wordpress.conf
a2dissite 000-default.conf

# Restart Apache to apply changes
systemctl restart apache2

# Check if Apache is running
if systemctl status apache2 | grep "active (running)"; then
    echo "Apache is running on port 3000."
else
    echo "Apache failed to start."
    exit 1
fi

# Install MariaDB
apt install -y mariadb-server mariadb-client
systemctl enable mariadb
systemctl start mariadb

# Secure MariaDB installation
mysql_secure_installation <<EOF

n
y
y
y
y
EOF

# Set up MySQL root password and create WordPress database and user
mysql -u root <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_password}';
CREATE DATABASE ${db_name};
CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Check if database and user were created successfully
if mysql -u root -p${mysql_root_password} -e "USE ${db_name}"; then
    echo "Database '${db_name}' created successfully."
else
    echo "Database creation failed."
    exit 1
fi

# Store MySQL root password in ~/.my.cnf for easier access
cat > ~/.my.cnf <<EOF
[client]
user=root
password=${mysql_root_password}
EOF
chmod 600 ~/.my.cnf

# Install PHP and required modules
apt install -y php libapache2-mod-php php-mysql php-cli php-curl php-xml php-mbstring php-gd

# Download and extract WordPress
install_dir="/var/www/html/wordpress"
mkdir -p ${install_dir}
cd /tmp
wget -q https://wordpress.org/wordpress-5.6.2.tar.gz
if [[ $? -ne 0 ]]; then
    echo "Failed to download WordPress."
    exit 1
fi

tar -xzf wordpress-5.6.2.tar.gz
mv wordpress/* ${install_dir}

# Check if WordPress files are in place
if [ -d "${install_dir}" ]; then
    echo "WordPress files extracted successfully."
else
    echo "WordPress extraction failed."
    exit 1
fi

# Set permissions
chown -R www-data:www-data ${install_dir}
chmod -R 755 ${install_dir}

# Configure WordPress wp-config.php
cp ${install_dir}/wp-config-sample.php ${install_dir}/wp-config.php

# Update wp-config.php with DB details
sed -i "s/database_name_here/${db_name}/" ${install_dir}/wp-config.php
sed -i "s/username_here/${db_user}/" ${install_dir}/wp-config.php
sed -i "s/password_here/${db_password}/" ${install_dir}/wp-config.php

# Add security keys (salts) to wp-config.php
# curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> ${install_dir}/wp-config.php

# Enable Apache mods for WordPress (rewrite for pretty permalinks)
a2enmod rewrite

# Restart Apache to apply changes
systemctl restart apache2

# Install WP-CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Install WordPress using WP-CLI
cd ${install_dir}
wp core install --url="http://${public_ip}" --title="My WordPress Site" --admin_user=${admin_user} --admin_password=${admin_password} --admin_email=${admin_email} --allow-root

# Install Nginx
apt install -y nginx
systemctl enable nginx

# Create NGINX config file
sudo bash -c 'cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF'

# Restart Nginx to apply changes
systemctl restart nginx

# Ensure ports are open in firewall (if ufw is used)
ufw allow 80/tcp
ufw allow 3000/tcp

# Final installation checks
if systemctl status apache2 | grep "active (running)" && mysql -u root -p${mysql_root_password} -e "USE ${db_name}"; then
    # Print out installation details only if everything is successful
    echo "Installation complete!"
    echo "WordPress has been installed in ${install_dir}"
    echo "Database Name: ${db_name}"
    echo "Database User: ${db_user}"
    echo "Database Password: ${db_password}"
    echo "MySQL root password: ${mysql_root_password}"
    echo "Apache is running on port 3000"
    echo "Nginx is running as a reverse proxy on port 80, forwarding to Apache on port 3000."
else
    echo "Installation failed. Please check the logs for more information."
    exit 1
fi

# Install theme
cd /var/www/html/wordpress
wp theme install https://downloads.wordpress.org/theme/spectra-one.1.1.5.zip --activate --allow-root
systemctl restart apache2
