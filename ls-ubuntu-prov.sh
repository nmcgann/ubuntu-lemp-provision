#!/bin/bash
#ubuntu 16.04 LTS on lightsail provisioning script
#also works for ubuntu/xenial64 box on vagrant
#everything runs as user ubuntu (nginx, fpm etc.)
start_seconds="$(date +%s)"

#leave logfile name empty to show on screen instead
LOGFILE=
#provision-log.log

MYSQL_ROOT_PASSWORD="admin"
DOMAIN1="testsite.co.uk"
#DOMAIN2 would be the www variant - not needed here
DOMAIN2=

HOME="/home/ubuntu"
#creates HOME/www as web root with www/public_html as public web location

#nginx main location block select - default does not url re-write to index.php
#default-main-block.conf
#wp-main-block.conf
MAIN_BLOCK=default-main-block.conf

#instance size options for mysql and php (based on the bitnami numbers)

#micro (query_cache_size innodb_buffer_pool_size)
#mysql_configs=( '8M' '16M' )
mysql_configs=( '16M' '32M' ) #try a bit bigger
#small
#mysql_configs=( '128M' '256M' )
#medium
#mysql_configs=( '128M' '256M' )
#large
#mysql_configs=( '256M' '2048M' )
#xlarge
#mysql_configs=( '256M' '2048M' )
#2xlarge
#mysql_configs=( '512M' '4096M' )

#php_configs=( pm.max_children pm.start_servers pm.min_spare_servers pm.max_spare_servers )
#micro
php_configs=( 5 1 1 3 )
#small
#php_configs=( 10 2 2 5 )
#medium
#php_configs=( 25 4 4 10 )
#large
#php_configs=( 50 5 5 30 )
#xlarge
#php_configs=( 125 6 6 50 )
#2xlarge
#php_configs=( 250 7 7 100 )

#logging
# save stdout & stderr to FD 6 & 7 so that they can be restored
# later and re-direct stout and stderr to the log file
if [ ! -z "${LOGFILE}" ]; then
exec 6>&1
exec 7>&2
exec 1> "${LOGFILE}" 2>&1
fi

#it's like whack-a-mole trying to keep update and upgrade non-interactive. 
#This is the best attempt so far.
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

#timezone
sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp true
sudo apt-get install -y ntpdate
sudo ntpdate pool.ntp.org

#fail2ban intrusion countermeasures (defaults are fine)
sudo apt-get install -y fail2ban
sudo service fail2ban start

#enable firewall
#sudo ufw default deny incoming
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
echo y | sudo ufw enable

#get the useful random pwgen utility and unzip
sudo apt-get install -y pwgen unzip

#useful editor defaults
cat <<EOF > .nanorc
set autoindent
set morespace
set nowrap
set tabsize 4
set tabstospaces
EOF

#install mysql 5.7
echo "mysql-server-5.7 mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | sudo debconf-set-selections
echo "mysql-server-5.7 mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | sudo debconf-set-selections
sudo apt-get install -y mysql-server

#harden default mysql installation
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

#configure mysql
cat << EOF | sudo tee /etc/mysql/mysql.conf.d/ubuntu-my.cnf > /dev/null
[mysqladmin]
user=root
[mysqld]
local-infile=0
max_allowed_packet=32M
bind-address=127.0.0.1
character-set-server=UTF8
collation-server=utf8_general_ci
long_query_time = 1
query_cache_limit=2M
query_cache_type=1
#micro size bitnami numbers
query_cache_size=${mysql_configs[0]}
innodb_buffer_pool_size=${mysql_configs[1]}
#
[client]
default-character-set=UTF8
EOF

sudo systemctl restart mysql

#install nginx
sudo add-apt-repository ppa:nginx/development -y
sudo apt-get install nginx -y

#configure nginx (basic)
sudo sed -i -r \
-e 's/^[ \t]*user www-data;/user ubuntu;/' \
-e 's/^([ \t]*worker_connections ).*/\1 1024;/' \
-e '/multi_accept/ c \\tmulti_accept on;' \
-e '/keepalive_timeout/ c \\tkeepalive_timeout 15;' \
-e '/server_tokens/ c \\tserver_tokens off;' \
-e '/server_tokens/ a \\tclient_max_body_size 64m;' \
-e '/gzip_proxied/ c \\tgzip_proxied any;' \
-e '/gzip_comp_level/ c \\tgzip_comp_level 2;' \
-e 's/#[ \t]*gzip_types/gzip_types/' \
-e '/default_type/ a \\tadd_header X-Frame-Options SAMEORIGIN;' \
-e '/default_type/ a \\tclient_max_body_size 64M;' \
/etc/nginx/nginx.conf

sudo service nginx restart

#install php 7
sudo add-apt-repository ppa:ondrej/php -y
sudo apt-get update

sudo apt-get install php7.1-fpm php7.1-common php7.1-mysqlnd php7.1-xmlrpc \
php7.1-curl php7.1-gd php7.1-imagick php7.1-cli php7.1-dev php7.1-imap \
php7.1-mcrypt php7.1-bcmath php7.1-mbstring php7.1-bz2 php7.1-zip php-pear -y

#memcaches (defaults to 64M on 127.0.0.1)
sudo apt-get -y install memcached
sudo apt-get -y install php-memcache php-memcached
#bit more ram
sudo sed -i -r 's/^-m[ \t]+64[ \t]*$/-m 96/' /etc/memcached.conf
sudo service php7.1-fpm restart

#configure fpm php daemon to use the main server user
#and set some params (micro bitnami size)
sudo sed -i -r \
-e '/^user =/ c user = ubuntu' \
-e '/^group =/ c group = ubuntu' \
-e '/^listen\.owner =/ c listen.owner = ubuntu' \
-e '/^listen\.group =/ c listen.group = ubuntu' \
-e '/^pm.max_children =/ c pm.max_children = '${php_configs[0]} \
-e '/^pm.start_servers =/ c pm.start_servers = '${php_configs[1]} \
-e '/^pm.min_spare_servers =/ c pm.min_spare_servers = '${php_configs[2]} \
-e '/^pm.max_spare_servers =/ c pm.max_spare_servers = '${php_configs[3]} \
-e '/^;?pm.max_requests =/ c pm.max_requests = 5000' \
/etc/php/7.1/fpm/pool.d/www.conf

#get certs for curl
sudo curl -s -o /etc/php/cacert.pem  https://curl.haxx.se/ca/cacert.pem

#configure php defaults
sudo sed -i -r \
-e '/^max_execution_time =/ c max_execution_time = 60' \
-e '/^post_max_size =/ c post_max_size = 64M' \
-e '/^;cgi.fix_pathinfo=/ c cgi.fix_pathinfo=0' \
-e '/^upload_max_filesize =/ c upload_max_filesize = 64M' \
-e '/^;date.timezone =/ c date.timezone = "UTC"' \
-e '/^session.use_strict_mode =/ c session.use_strict_mode = 1' \
-e '/^session.gc_probability =/ c session.gc_probability = 100' \
-e '/^session.gc_maxlifetime =/ c session.gc_maxlifetime = 14400' \
-e '/^;curl.cainfo =/ c curl.cainfo = /etc/php/cacert.pem' \
/etc/php/7.1/fpm/php.ini

#ensure session dir owned by same user as php
sudo chown -R ubuntu:ubuntu /var/lib/php/sessions
sudo chmod -R 0755 /var/lib/php/sessions/

sudo service php7.1-fpm restart

#get php opcache tool and make a convenient reset command
#http://gordalina.github.io/cachetool/
curl -s -O http://gordalina.github.io/cachetool/downloads/cachetool.phar
chmod +x cachetool.phar
echo "${HOME}/cachetool.phar opcache:reset --fcgi=/run/php/php7.1-fpm.sock" > php-opcache-reset.sh
chmod +x php-opcache-reset.sh

#load the most useful pear packages (mail with SMTP)
sudo pear channel-update pear.php.net
sudo pear install --alldeps Mail Mail_Mime Net_SMTP

#remove default site
sudo rm /etc/nginx/sites-enabled/default > /dev/null 2>&1

#add new default after all others as "not available"
sudo sed -i -r \
-e '/include \/etc\/nginx\/sites-enabled\/\*;/ a\
    #default server block\
    server{\
        listen 80 default_server;\
        server_name _;\
        return 444;\
    }' \
/etc/nginx/nginx.conf

#add additional SSL config (will currently get an A in the tests)
sudo sed -i -r \
-e '/ssl_prefer_server_ciphers on;/ a\
        ssl_ciphers  HIGH:!aNULL:!MD5;\
        ssl_session_cache shared:SSL:10m;\
        ssl_session_timeout 10m;\
        #add_header Strict-Transport-Security "max-age=31536000; includeSubdomains";\
    ' \
/etc/nginx/nginx.conf

sudo service nginx restart

#make web root
[ ! -d "${HOME}/www" ] && \
mkdir "${HOME}"/www

#ensure web root is under correct ownership (if running in vagrant with mapped public_html this can get created as root)
sudo chown ubuntu:ubuntu "${HOME}"/www
chmod 0755 "${HOME}"/www

#download mysql admin tool (need to follow redirects)
curl -s -L -o adminer.php https://www.adminer.org/latest-mysql-en.php

#create a directory to be aliased in to the webroot
[ ! -d "${HOME}/adminer" ] && \
mkdir "${HOME}"/adminer

mv adminer.php "${HOME}"/adminer/adminer.php
sudo chown -R ubuntu:ubuntu adminer

#set up log directory and public html root
[ ! -d "${HOME}/www/public_html" ] && \
mkdir "${HOME}"/www/public_html

[ ! -d "${HOME}/logs" ] && \
mkdir "${HOME}"/logs

#make directory for Lets Encrypt (used later)
[ ! -d "${HOME}/.well-known/acme-challenge" ] && \
mkdir -p "${HOME}"/.well-known/acme-challenge

#make sure web directory and file permissions are consistent
sudo find "${HOME}"/www/ -type d -not -perm 0755 -exec chmod 0755 '{}' \;
sudo find "${HOME}"/www/ -type f -not -perm 0644 -exec chmod 0644 '{}' \;

#make directory for extra configs to load from nginx server blocks
[ ! -d "/etc/nginx/sites-available/configs" ] && \
sudo mkdir /etc/nginx/sites-available/configs

#make self-signed dummy certs
sudo openssl req -subj "/O=TEST-DEV/C=UK/CN=${DOMAIN1}" -new -newkey rsa:2048 \
-days 365 -nodes -x509 -keyout /etc/nginx/server.key -out /etc/nginx/server.crt > /dev/null
sudo chmod 0600 /etc/nginx/server.key

#create main server config
cat << EOF | sudo tee /etc/nginx/sites-available/${DOMAIN1} > /dev/null
server {
    listen 80;
    listen 443 ssl;

    #temporary certs for testing
    ssl_certificate "/etc/nginx/server.crt";
    ssl_certificate_key "/etc/nginx/server.key";

    server_name ${DOMAIN1} ${DOMAIN2};

    access_log /home/ubuntu/logs/access.log;
    error_log /home/ubuntu/logs/error.log;

    root /home/ubuntu/www/public_html/;
    index index.php;

    #pull in other locations and configs (eg. wordpress config)
    include sites-available/configs/extra-config.conf;

    #alias acme dir for Lets Encrypt (used later)
    location /.well-known {
        alias "/home/ubuntu/.well-known";
        #index for testing only
        index index.html;

        allow all;
    }
	#main block
    include sites-available/configs/main-location-block.conf;

    #main php (linked to php.conf unless caching added)
    include sites-available/configs/php-main.conf;
}
EOF


cat << EOF | sudo tee /etc/nginx/sites-available/localhost > /dev/null
#localhost server for ssh tunneled connections
server {
    listen 80;

    server_name localhost 127.0.0.1;

    access_log /home/ubuntu/logs/access.log;
    error_log /home/ubuntu/logs/error.log;

    root /home/ubuntu/www/public_html/;
    index index.php;

    #pull in other locations and configs
    include sites-available/configs/local-extra-config.conf;
    
    #alias adminer dir
    location /adminer {
        alias "/home/ubuntu/adminer";
        index adminer.php;

        allow 127.0.0.1; #local access only (via ssh tunnel)
        deny all;
        
        include sites-available/configs/php.conf;
    }
    
    location / {
        try_files \$uri \$uri/ =404; 
    }
    
    include sites-available/configs/php.conf;    
}

EOF

#generic php config
cat << EOF | sudo tee /etc/nginx/sites-available/configs/php.conf > /dev/null
    location ~ \.php\$ {
        try_files \$uri =404;
        #fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php7.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$request_filename;
        include fastcgi_params;
    }
EOF

#main location blocks
cat << EOF | sudo tee /etc/nginx/sites-available/configs/default-main-block.conf > /dev/null
#standard main nginx location block
location / {
        try_files \$uri \$uri/ =404;
}
EOF

cat << EOF | sudo tee /etc/nginx/sites-available/configs/wp-main-block.conf > /dev/null
#wp location block
location / {
        try_files \$uri \$uri/ /index.php?\$args;
}
EOF

#link standard location block
sudo ln -s /etc/nginx/sites-available/configs/${MAIN_BLOCK} \
/etc/nginx/sites-available/configs/main-location-block.conf > /dev/null 2>&1

#link standard php
sudo ln -s /etc/nginx/sites-available/configs/php.conf \
/etc/nginx/sites-available/configs/php-main.conf > /dev/null 2>&1

#add empty placemarker config file (would get filled in with wp extra config)
cat << EOF | sudo tee /etc/nginx/sites-available/configs/extra-config.conf > /dev/null
EOF

#add empty placemarker config file for localhost
cat << EOF | sudo tee /etc/nginx/sites-available/configs/local-extra-config.conf > /dev/null
EOF

#enable domain configs
sudo ln -s /etc/nginx/sites-available/${DOMAIN1} /etc/nginx/sites-enabled/${DOMAIN1} > /dev/null 2>&1
sudo ln -s /etc/nginx/sites-available/localhost /etc/nginx/sites-enabled/localhost > /dev/null 2>&1

sudo service nginx restart

end_seconds="$(date +%s)"
echo "---------------------------------------------------------------------"
echo "Provisioning complete in "$(( end_seconds - start_seconds ))" seconds"
echo "Ubuntu server setup complete (Mysql 5.7, Nginx, PHP-FPM 7.1)."

#logging: restore stdout/stderr (and close descriptors 6 and 7)
if [ ! -z "${LOGFILE}" ]; then
exec 1>&6 6>&-
exec 2>&7 7>&-
echo "Provision done. See ${LOGFILE} for details."
fi

#end
