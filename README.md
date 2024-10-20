# challenge-cloudresume-aws-level-0
How to setup your first web app on AWS EC2, VPC and IGW

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

