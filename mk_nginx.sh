#!/usr/bin/env bash

set -o errtrace
set -o nounset
set -o errexit

readonly CURPATH="$(readlink -f "$(dirname "$0")")"
:<<"EOF"
for SM2 ssl replace:
--with-openssl=${CURPATH}/wotrus_ssl2.0

auto/lib/openssl/conf
 39             CORE_INCS="$CORE_INCS $OPENSSL/include"
 40             CORE_DEPS="$CORE_DEPS $OPENSSL/include/openssl/ssl.h"
 41             CORE_LIBS="$CORE_LIBS $OPENSSL/lib/libssl.a"
 42             CORE_LIBS="$CORE_LIBS $OPENSSL/lib/libcrypto.a"
EOF
./configure --prefix=/usr/share/nginx \
--sbin-path=/usr/sbin/nginx \
--conf-path=/etc/nginx/nginx.conf \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--pid-path=/run/nginx.pid \
--lock-path=/var/lock/nginx.lock \
--http-client-body-temp-path=/var/lib/nginx/body \
--http-proxy-temp-path=/var/lib/nginx/proxy \
--http-fastcgi-temp-path=/var/lib/nginx/fastcfg \
--http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
--http-scgi-temp-path=/var/lib/nginx/scgi \
--with-pcre-jit \
--with-threads \
--with-file-aio \
--with-http_ssl_module \
--with-http_realip_module \
--with-http_addition_module \
--with-http_sub_module \
--with-http_gunzip_module \
--with-http_gzip_static_module \
--with-http_auth_request_module \
--with-http_secure_link_module \
--with-http_slice_module \
--with-http_stub_status_module \
--with-stream \
--with-stream_ssl_module \
--with-stream_realip_module \
--with-stream_ssl_preread_module \
 \
--with-http_geoip_module=dynamic \
--with-stream_geoip_module=dynamic \
 \
--with-openssl=${CURPATH}/openssl-1.1.0f \
--with-pcre=${CURPATH}/pcre-8.39 \
--with-zlib=${CURPATH}/zlib-1.2.11.dfsg \
--add-module=nginx-goodies-nginx-sticky-module-ng-08a395c66e42 \
--add-module=nginx_limit_speed_module-master \
--add-module=nginx-module-vts-master \
--add-module=ngx_http_redis-0.3.9 \
--add-module=nginx-eval-module-master

readonly OUTDIR=${CURPATH}/out
rm -rf ${OUTDIR}
mkdir -p ${OUTDIR}
make install DESTDIR=${OUTDIR}

echo "/usr/lib/tmpfiles.d/nginx.conf"
mkdir -p ${OUTDIR}/usr/lib/tmpfiles.d/
cat <<'EOF' > ${OUTDIR}/usr/lib/tmpfiles.d/nginx.conf
d /var/lib/nginx 0755 root root -
d /var/log/nginx 0755 root root -
EOF
echo "/usr/lib/systemd/system/nginx.service"
mkdir -p ${OUTDIR}/usr/lib/systemd/system/
cat <<'EOF' > ${OUTDIR}/usr/lib/systemd/system/nginx.service
[Unit]
Description=The nginx HTTP and reverse proxy server
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
# Nginx will fail to start if /run/nginx.pid already exists but has the wrong
# SELinux context. This might happen when running `nginx -t` from the cmdline.
# https://bugzilla.redhat.com/show_bug.cgi?id=1268621
ExecStartPre=/usr/bin/rm -f /run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
KillSignal=SIGQUIT
TimeoutStopSec=5
KillMode=process
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

echo "/etc/logrotate.d/nginx"
mkdir -p ${OUTDIR}/etc/logrotate.d/
cat <<'EOF' > ${OUTDIR}/etc/logrotate.d/nginx 
/var/log/nginx/*log {
    create 0644 root root
    daily
    rotate 40
    missingok
    notifempty
    compress
    sharedscripts
    postrotate
        /bin/kill -USR1 `cat /run/nginx.pid 2>/dev/null` 2>/dev/null || true
    endscript
}
EOF

mkdir -p ${OUTDIR}/etc/nginx/http-conf.d/
mkdir -p ${OUTDIR}/etc/nginx/stream-conf.d/
mkdir -p ${OUTDIR}/etc/nginx/http-enabled/
mkdir -p ${OUTDIR}/etc/nginx/stream-enabled/
mkdir -p ${OUTDIR}/etc/nginx/http-available/
mkdir -p ${OUTDIR}/etc/nginx/stream-available/

cat <<EOF >${OUTDIR}/etc/nginx/http-available/speed_limit_demo.conf
server {
    listen 82;
    location /download/ {
        limit_speed one 100k;
    }
}
EOF

cat <<'EOF' >${OUTDIR}/etc/nginx/http-available/redis.conf
# redis-cli -x set curl/7.64.0 http://srv1
# redis-cli -x set curl/7.61.1 http://www.xxx.com
upstream srv1 {
    sticky;
    server 192.168.1.100:80;
}

upstream redis {
    server 127.0.0.1:6379;
}

server {
    listen 81;
    location / {
        # cache !!!!
        set $redis_key $uri;
        redis_pass     redis;
        default_type   text/html;
        error_page     404 = /real_server;
    }
    location = /fallback {
        proxy_pass real_server;
    }

    location /redis-test {
        eval_escalate on;
        eval $answer {
            set $redis_key "$http_user_agent";
            redis_pass redis;
        }
        proxy_pass $answer;
        error_page 404 502 504 = @fallback;
    }
    location @fallback {
        proxy_pass https://www.xxx.com;
    }
    # gzip -c index.html | redis-cli -x set /index.html
    # gzip -c index.html | redis-cli -x set /
    location /test/ {
        gunzip on;
        redis_gzip_flag 1;
        set $redis_key "$uri";
        redis_pass redis;
    }
    # location /test2/ {
    #     set $redis_key "$uri?$args";
    #     redis_pass 127.0.0.1:6379;
    #     error_page 404 502 504 = @fallback;
    # }
    # location @fallback {
    #     proxy_pass backed;
    # }
}
EOF


cat <<'EOF' >${OUTDIR}/etc/nginx/http-available/traffic_status.conf
# /{status_uri}/control?cmd=*`{command}`*&group=*`{group}`*&zone=*`{name}`*
# /control?cmd=reset&group=server&zone=*
server {
    listen 80;
    # listen 443 ssl;
    # ssl_certificate /etc/nginx/SSL/ca.pem
    # ssl_certificate_key /etc/nginx/SSL/site.key;
    # server_name status.example.org;
    # # force https
    # proxy_redirect http:// $scheme://;
    # if ($scheme = http ) {
    #     return 301 https://$server_name$request_uri;
    # }

    location / {
        vhost_traffic_status_display;
        vhost_traffic_status_display_format html;
    }
}
EOF

cat <<'EOF' > ${OUTDIR}/etc/nginx/http-conf.d/proxy.conf
client_max_body_size 100M;
proxy_ignore_client_abort on;
server_names_hash_max_size 1024;
proxy_headers_hash_max_size 102400;
proxy_headers_hash_bucket_size 10240;
client_header_buffer_size 40k;
large_client_header_buffers 4 80k;
EOF

cat <<'EOF' > ${OUTDIR}/etc/nginx/http-conf.d/httplog.conf
log_format main '$scheme $http_host [$request_time|$upstream_response_time|$upstream_status] '
              '$remote_addr - $remote_user [$time_local] "$request" '
              '$status $body_bytes_sent "$http_referer" '
              '"$http_user_agent" "$http_x_forwarded_for" $gzip_ratio';

geo $remote_addr $log_ip {
#    10.3.0.0/16 0;
    default 1;
}

map $status $log_err {
#    502 1;
#    503 1;
#    504 1;
    default 0;
}
access_log /var/log/nginx/access_err.log main if=$log_err;
access_log /var/log/nginx/access.log main if=$log_ip;
# separate access logs from requests of two different domains
# access_log /var/log/nginx/$http_host-access.log;
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/stream-conf.d/streamlog.conf
log_format basic '$remote_addr $protocol $server_port [$time_local] '
                 '$status $bytes_sent $bytes_received '
                 '$session_time';

access_log /var/log/nginx/stream_access.log basic buffer=32k;
error_log /var/log/nginx/stream_error.log;
EOF

cat <<'EOF' > ${OUTDIR}/etc/nginx/nginx.conf
user www-data;
worker_processes auto;
worker_rlimit_nofile 102400;
pid /run/nginx.pid;

# load_module modules/ngx_http_geoip_module.so;
# load_module modules/ngx_stream_geoip_module.so;

events {
    use epoll;
    worker_connections 10240;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    types_hash_max_size 2048;
    server_tokens off;

    # # allow the server to close connection on non responding client, this will free up memory
    reset_timedout_connection on;

    # # number of requests client can make over keep-alive -- for testing environment
    keepalive_requests 1000;
    proxy_next_upstream error timeout invalid_header;
    proxy_intercept_errors on;
    proxy_redirect off;
    proxy_set_header Host $host:$server_port;
    proxy_redirect http:// $scheme://;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Connection "";
    proxy_http_version 1.1;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # # SSL
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
    ssl_prefer_server_ciphers on;

    # # error log
    error_log /var/log/nginx/error.log;

    # # gzip
    gzip on;
    gzip_static on;
    gzip_buffers 16 8k;
    gzip_comp_level 6;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        text/xml application/xml application/atom+xml application/rss+xml application/xhtml+xml image/svg+xml
        text/javascript application/javascript application/x-javascript
        text/x-json application/json application/x-web-app-manifest+json
        text/css text/plain text/x-component
        font/opentype application/x-font-ttf application/vnd.ms-fontobject
        image/x-icon;
    gzip_disable "msie6";

    # # geoip module
    # geoip_country /usr/share/GeoIP/GeoIP.dat;

    # # traffic_status module
    vhost_traffic_status_zone;
    # vhost_traffic_status_filter_by_set_key $geoip_country_code country::*;

    # # limit speed module
    limit_speed_zone one $binary_remote_addr 10m;

    # # vhost include
    include /etc/nginx/http-conf.d/*.conf;
    include /etc/nginx/http-enabled/*;
}

stream {
    include /etc/nginx/stream-conf.d/*.conf;
    include /etc/nginx/stream-enabled/*;
}
EOF

# gem install fpm
# fpm -s dir -t rpm -C ~/nginx-1.13.0/bin/ --name nginx_xikang --version 1.13.0 --iteration 1 --depends pcre --depends zlib --description "xikang nginx with openssl,other modules" .

