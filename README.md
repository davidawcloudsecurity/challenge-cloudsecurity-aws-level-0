# challenge-cloudresume-aws-level-0
How to setup your first web app on AWS EC2, VPC and IGW
## Run this if you know how to install terraform in cloudshell
```bash
alias tf="terraform"; alias tfa="terraform apply --auto-approve"; alias tfd="terraform destroy --auto-approve"; alias tfm="terraform init; terraform fmt; terraform validate; terraform plan"; sudo yum install -y yum-utils shadow-utils; sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; sudo yum -y install terraform; terraform init
```
## Run the following to setup as per your experience
If you want to setup WordPress with custom title, username, and password
```bash
tfa -var setup_filename=setup_wordpress.sh
```
If you want to setup WordPress with default title, username and password
```bash
tfa -var setup_filename=setup_wordpress_ready_state.sh
```
If you want to setup WordPress with nginx, default title, username and password
```bash
tfa -var setup_filename=setup_wordpress_nginx_ready_state.sh
```
## Setup apache2 for Wordpress for port 3000
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
## Use Certbot
```bash
sudo apt install certbot python3-certbot-nginx -y
example=dns
sudo certbot --nginx -d $example -d www.${example} # interactive
sudo certbot --nginx -d $example --non-interactive --agree-tos --email your-email@${example} # non interactive
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
/etc/nginx/site-enabled
/etc/nginx/sites-available
```
## Themes for different types of online business
```bash
1. Install a Theme from WordPress Repository
To install a theme from the WordPress repository, use the wp theme install command. For example, to install the Twenty Twenty-Three theme:

bash
Copy code
wp theme install twentytwentythree
This will download and install the theme. If you also want to activate it immediately, add the --activate flag:

bash
Copy code
wp theme install twentytwentythree --activate
2. Install a Theme from a URL
If you have a custom theme hosted somewhere (like on GitHub or a zip file on another server), you can install it from a URL. Here's an example:

bash
Copy code
wp theme install https://example.com/path/to/theme.zip
If you want to activate the theme immediately after installation, use the --activate flag:

bash
Copy code
wp theme install https://example.com/path/to/theme.zip --activate
3. Upload and Install a Local Theme
If you have a theme locally as a .zip file, you can manually upload it using the command:

bash
Copy code
wp theme install /path/to/theme.zip
This installs the theme from the local .zip file. Add the --activate flag if you want to activate it upon installation.

Additional WP-CLI Theme Commands
To update a theme:

bash
Copy code
wp theme update theme-name
To delete a theme:

bash
Copy code
wp theme delete theme-name
```

Consulting
```bash
https://wordpress.org/themes/envo-royal/
https://wordpress.org/themes/spectra-one/
https://wordpress.org/themes/zeever/
https://wordpress.org/themes/zatra/
https://wordpress.org/themes/bakery-and-pastry/
https://wordpress.org/themes/monify-lite/
https://wordpress.org/themes/photolancer/
```
Blog
```bash
https://wordpress.org/themes/colibri-wp/
https://wordpress.org/themes/newsexo/
https://wordpress.org/themes/inspiro/
https://wordpress.org/themes/kubio/

```
ecommerce
```bash
https://wordpress.org/themes/bloghash/
```

## Resource
How to change url of wordpress using wordpress cli
```bash
public_ip=$(curl ifconfig.me)
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
### To do
how to protect using guardduty - https://dev.to/vumdao/aws-guardduty-combine-with-security-hub-and-slack-17eh

Use this to remove snapshot and ami in robot branch - https://developer.hashicorp.com/terraform/language/resources/provisioners/syntax#destroy-time-provisioners
```bash
Put this in null resource to create instance if filename is robot ova
https://docs.aws.amazon.com/cli/v1/userguide/cli-services-ec2-instances.html
https://devopscube.com/use-aws-cli-create-ec2-instance/
```


