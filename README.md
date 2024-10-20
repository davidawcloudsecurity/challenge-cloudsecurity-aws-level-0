# challenge-cloudresume-aws-level-0
How to setup your first web app on AWS EC2, VPC and IGW
## Setup apache2 for Wordpress
```bash
<VirtualHost *:3000>
    DocumentRoot /var/www/html/wordpress
    <Directory /var/www/html/wordpress>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```
## Setup nginx
```bash
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```
## Troubleshoot
How to read logs
```bash
sudo tail -f /var/log/apache2/access.log
sudo tail -f /var/log/apache2/error.log
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```
How to read files
```bash
/etc/apache2/sites-available/000-default.conf
/etc/nginx/conf.d
```
## Resource
How to change url of wordpress using wordpress cli
```bash
public_ip=<IP/DNS>
wp option update siteurl "http://$public_ip" --allow-root
wp option update home "http://$public_ip" --allow-root
```
How to change url of wordpress using mysql
```bash
mysql -u root -p${mysql_root_password} -e "USE ${db_name}; UPDATE wp_options SET option_value='http://${public_ip}' WHERE option_name='siteurl' OR option_name='home';"
```
How to change url of wordpress manually
```bash
nano /var/www/html/wordpress/wp-config.php
# Look for these
define('WP_HOME', 'http://54.221.120.0:3000');
define('WP_SITEURL', 'http://54.221.120.0:3000');
```
Restart apache2
```bash
sudo systemctl restart apache2
```

