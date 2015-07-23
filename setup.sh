#!/bin/false
# DO NOT RUN THIS DIRECTLY

git submodule init && git submodule update

# base blank image
tar cv --files-from /dev/null | docker import - blank

# archlinux
docker build -t archlinux docker-archlinux-odroidxu3/

# mariadb
docker build -t mariadb docker-mariadb-archlinux/
docker create --name mariadb-data -v /var/lib/mysql blank ""
docker create --name mariadb-unixsocket -v /run/mysqld:/var/run/mysqld blank ""
docker run --name mariadb -p 127.0.0.1:3306:3306 -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD -d --volumes-from mariadb-data --volumes-from mariadb-unixsocket mariadb
# monitor setup progress
docker logs mariadb
# after setup complete
docker stop mariadb
docker rm mariadb
docker create --name mariadb -p 127.0.0.1:3306:3306 --volumes-from mariadb-data --volumes-from mariadb-unixsocket mariadb
if [ -f /etc/systemd/system/mariadb.service ]; then cp systemd-services/mariadb.service /etc/systemd/system/mariadb.service && sudo systemctl daemon-reload && sudo systemctl enable mariadb && sudo systemctl start mariadb; else echo "mariadb.service file not copied since it exists; do it on your own."; fi

# redis
docker build -t redis docker-redis-armhf/3.0/
docker create --name redis-data -v /data blank ""
docker create --name redis --volumes-from redis-data redis redis-server --appendonly yes
if [ -f /etc/systemd/system/redis.service ]; then cp systemd-services/redis.service /etc/systemd/system/redis.service && sudo systemctl daemon-reload && sudo systemctl enable redis && sudo systemctl start redis; else echo "redis.service file not copied since it exists; do it on your own."; fi

# mount /data
docker create --name data-mount -v /data:/data blank ""

# web data
docker build -t nginx docker-nginx-archlinux
docker create --name nginx-conf -v /etc/nginx:/etc/nginx blank ""
docker create --name web-data -v /var/www:/var/www blank ""
mkdir $(pwd)/nginx-default-conf
docker run -it --rm -v $(pwd)/nginx-default-conf:/temp nginx bash -c "mkdir -p /temp/etc /temp/usr/share && cp -r /etc/nginx /temp/etc && cp -r /usr/share/nginx /temp/usr/share"
docker run -it --rm -v $(pwd)/nginx-default-conf:/temp --volumes-from web-data --volumes-from nginx-conf archlinux bash -c "cp -r /temp/etc/nginx/* /etc/nginx && cp -r /temp/usr/share/nginx/* /var/www"

# php
docker build -t php:fpm docker-php-armhf/5.6/fpm
docker build --rm -t=php:fpm-ext docker-php-fpm-ext
docker create --name php-fpm-unixsocket -v /run/php-fpm:/run/php-fpm blank ""
docker create --name php-fpm --volumes-from web-data \
	      --volumes-from php-fpm-unixsocket \
	      --volumes-from mariadb-unixsocket \
	      --volumes-from data-mount \
              --link redis:redis --link mariadb:mariadb php:fpm-ext
if [ -f /etc/systemd/system/php-fpm.service ]; then cp systemd-services/php-fpm.service /etc/systemd/system/php-fpm.service && sudo systemctl daemon-reload && sudo systemctl enable php-fpm && sudo systemctl start php-fpm; else echo "php-fpm.service file not copied since it exists; do it on your own."; fi

# nginx
docker create --name nginx --volumes-from web-data --volumes-from nginx-conf --volumes-from data-mount --volumes-from php-fpm-unixsocket --link php-fpm:php -p 80:80 -p 443:443 nginx
if [ -f /etc/systemd/system/nginx.service ]; then cp systemd-services/nginx.service /etc/systemd/system/nginx.service && sudo systemctl daemon-reload && sudo systemctl enable nginx && sudo systemctl start nginx; else echo "nginx.service file not copied since it exists; do it on your own."; fi

# owncloud cron runner
# use same parameters excluding php-unixsocket from php
# currently not working; no reason was found yet
# docker create --name owncloud-cron --volumes-from web-data \
#               --volumes-from mariadb-unixsocket \
#               --volumes-from data-mount \
#               --link redis:redis --link mariadb:mariadb php:fpm-ext php -f /var/www/hosts/$OWNCLOUD_HOSTNAME/public_html/cron.php

# owncloud file indexer
docker create --name owncloud-indexer --volumes-from web-data \
              --volumes-from mariadb-unixsocket \
              --volumes-from data-mount \
              --link redis:redis --link mariadb:mariadb php:fpm-ext sudo -uwww-data php -f /var/www/hosts/$OWNCLOUD_HOSTNAME/public_html/console.php files:scan --all > /dev/null
if [ -f /etc/systemd/system/owncloud-cron.service && -f /etc/systemd/system/owncloud-cron.timer ]; then cp systemd-services/owncloud-cron.* /etc/systemd/system/ && sudo systemctl daemon-reload && echo "Please modify /etc/systemd/system/owncloud-cron.service file to suit your setup and enable and run it."; else echo "owncloud-cron.service/timer file not copied since it exists; do it on your own."; fi
