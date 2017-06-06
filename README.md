# ubuntu-lemp-provision
Provisioning shell script for LEMP stack on Ubuntu 16.04 (Aws Lightsail and Vagrant "ubuntu/xenial64" versions tested).

Installs:
* timedatectl
* ntpdate
* fail2ban
* pwgen 
* unzip
* mysql 5.7 (root password is "admin")
* nginx (from ppa:nginx/development)
* php7.1 (from ppa:ondrej/php)
* php7.1-fpm (for nginx)
* memcached
* https://curl.haxx.se/ca/cacert.pem (for curl)
* http://gordalina.github.io/cachetool/downloads/cachetool.phar
* pear: Mail Mail_Mime Net_SMTP
* https://www.adminer.org/latest-mysql-en.php (PhpMyAdmin alternative)

Creates a self-signed ssl certificate for Nginx.

Responding site is testsite.co.uk. ufw is configured to allow http, https and ssh to pass.

Everything runs as user "ubuntu", group "ubuntu".

Adminer is found at http://testsite.co.uk/adminer/adminer.php (aliased). It is only accessible from
localhost, a ssh tunnel is needed to allow remote access.

Let's encrypt directory is present at  http://testsite.co.uk/.well-known/acme-challenge (aliased).

Web root is /home/ubuntu/www and public web directory is /home/ubuntu/www/public_html. This structure is easy to map with
vagrant for local development.

See https://deliciousbrains.com/hosting-wordpress-2017-update/ for a great series on configuring nginx. This was
the main source of ideas on nginx configuration expanded into the more general setup here.