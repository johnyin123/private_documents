#!/usr/bin/env bash
VERSION+=("3e119a9[2021-11-24T09:28:26+08:00]:mk_nginx.sh")

set -o errtrace
set -o nounset
set -o errexit

readonly CURPATH="$(readlink -f "$(dirname "$0")")"
readonly OUTDIR=${CURPATH}/out

:<<"EOF"
for SM2 ssl replace:
--with-openssl=${CURPATH}/wotrus_ssl2.0

auto/lib/openssl/conf
 39             CORE_INCS="$CORE_INCS $OPENSSL/include"
 40             CORE_DEPS="$CORE_DEPS $OPENSSL/include/openssl/ssl.h"
 41             CORE_LIBS="$CORE_LIBS $OPENSSL/lib/libssl.a"
 42             CORE_LIBS="$CORE_LIBS $OPENSSL/lib/libcrypto.a"
EOF

:<<"EOF"
=：精确匹配，优先级最高。如果找到了这个精确匹配，则停止查找。
^~：URI 以某个常规字符串开头，不是正则匹配
~：区分大小写的正则匹配
~*：不区分大小写的正则匹配
/：通用匹配, 优先级最低。任何请求都会匹配到这个规则
EOF
# geoip static error
# --with-http_geoip_module=dynamic \
# --with-stream_geoip_module=dynamic \

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
 \
--with-compat \
 \
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
--with-http_random_index_module \
--with-http_dav_module \
 \
--with-http_flv_module \
--with-http_mp4_module \
 \
--with-stream \
--with-stream_ssl_module \
--with-stream_realip_module \
--with-stream_ssl_preread_module \
 \
--with-openssl=${CURPATH}/openssl-1.1.1l \
--with-pcre=${CURPATH}/pcre-8.39 \
--with-zlib=${CURPATH}/zlib-1.2.11.dfsg \
--add-module=nginx-goodies-nginx-sticky-module-ng-08a395c66e42 \
--add-module=nginx_limit_speed_module-master \
--add-module=nginx-module-vts-master \
--add-module=ngx_http_redis-0.3.9 \
--add-module=nginx-eval-module-master \
--add-module=nginx-rtmp-module-1.2.2


echo "${VERSION[@]}**************************************************"
sed -i "s/NGX_CONFIGURE\s*.*$/NGX_CONFIGURE \"${VERSION[@]} by johnyin\"/g" objs/ngx_auto_config.h
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
cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta content="text/html; charset=utf-8" http-equiv="Content-Type">
    <title>flv.js demo</title>
    <style>
        .mainContainer {
    display: block;
    width: 1024px;
    margin-left: auto;
    margin-right: auto;
}
.urlInput {
    display: block;
    width: 100%;
    margin-left: auto;
    margin-right: auto;
    margin-top: 8px;
    margin-bottom: 8px;
}

.centeredVideo {
    display: block;
    width: 100%;
    height: 576px;
    margin-left: auto;
    margin-right: auto;
    margin-bottom: auto;
}

.controls {
    display: block;
    width: 100%;
    text-align: left;
    margin-left: auto;
    margin-right: auto;
}
    </style>
</head>

<body>
    <div class="mainContainer">
        <video id="videoElement" class="centeredVideo" controls autoplay width="1024" height="576">Your browser is too old which doesn't support HTML5 video.</video>
    </div>
    <br>
    <div class="controls">
        <!--<button onclick="flv_load()">加载</button>-->
        <button onclick="flv_start()">开始</button>
        <button onclick="flv_pause()">暂停</button>
        <button onclick="flv_destroy()">停止</button>
        <input style="width:100px" type="text" name="seekpoint" />
        <button onclick="flv_seekto()">跳转</button>
    </div>
    <script src="flv.min.js"></script>
    <script>
        var player = document.getElementById('videoElement');
        if (flvjs.isSupported()) {
            var flvPlayer = flvjs.createPlayer({
                type: 'flv',
                // "isLive": true,
                url: '你的视频.flv'
            });
            flvPlayer.attachMediaElement(videoElement);
            flvPlayer.load(); //加载
        }

        function flv_start() {
            player.play();
        }

        function flv_pause() {
            player.pause();
        }

        function flv_destroy() {
            player.pause();
            player.unload();
            player.detachMediaElement();
            player.destroy();
            player = null;
        }

        function flv_seekto() {
            player.currentTime = parseFloat(document.getElementsByName('seekpoint')[0].value);
        }
    </script>
</body>
</html>
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/http-available/flv_movie.conf
# flv mp4流媒体服务器, https://github.com/Bilibili/flv.js
# apt -y install yamdi
server {
    listen       80;
    root    /movie/;
    limit_rate_after 5m; #在flv视频文件下载了5M以后开始限速
    limit_rate 100k;     #速度限制为100K
    index index.html;
    location ~ \.flv {
        flv;
    }
}
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/http-available/fcgiwrap.conf
# apt -y install fcgiwrap
# mkdir -p /var/www/cgi-bin && chmod 755 /var/www/cgi-bin
# cat <<CGIEOF > /var/www/cgi-bin/test.cgi
# #!/bin/bash
# printf "Content-type: text/html\n\n"
# cat << EDOC
# <html><body>CGI Script Test Page</body></html>"
# EDOC
# CGIEOF
# chmod 755 /var/www/cgi-bin/test.cgi
# systemctl enable fcgiwrap --now
# curl localhost/cgi-bin/test.cgi
server {
    listen 80;
    location /cgi-bin/ {
        gzip off;
        root /var/www;
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/http-available/secure_link.conf
map $uri $allow_file {
    default none;
    "~*/s/(?<name>.*).txt" $name;
    "~*/s/(?<name>.*).mp4" $name;
}
# mkdir -p /var/www/secure/hls/ && echo "HLS FILE" > /var/www/secure/hls/file.txt
# mkdir -p /var/www/files/ && echo "FILES FILE" > /var/www/files/file.txt
# mkdir -p /var/www/s/ && echo "S FILE" > /var/www/s/file.txt
server {
    listen 80;
    ## Basic Secured URLs
    # echo -n 'hls/file.txtprekey' | openssl md5 -hex
    # curl http://${srv}/videos/071f5f362f9362f1d14a3ece3b0c37e6/hls/file.txt
    location /videos {
        secure_link_secret prekey;
        if ($secure_link = "") { return 403; }
        rewrite ^ /secure/$secure_link;
    }
    location /secure {
        internal;
        root /var/www;
    }
    ## Secured URLs that Expire
    # sec=3600
    # expire=$(date -d "+${sec} second" +%s)
    # client_ip=192.168.168.1
    # echo -n "${expire}/files/file.txt${client_ip} prekey" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =
    # curl --interface "${client_ip}" "http://${srv}/files/file.txt?k=XXXXXXXXXXXXXX&e=${expire}"
    location /files {
        root /var/www;
        secure_link $arg_k,$arg_e;
        secure_link_md5 "$secure_link_expires$uri$remote_addr prekey";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
    }
    ## Securing Segment Files with an Expiration Date
    # agent="curl/7.74.0"
    # echo -n "prekey${expire}file${agent}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =
    # curl "http://${srv}/s/file.txt?md5=XXXXXXXXXXXXXX&expires=${expire}"
    location /s {
        root /var/www;
        secure_link $arg_md5,$arg_expires;
        secure_link_md5 "prekey$secure_link_expires$allow_file$http_user_agent";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
    }
}
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/http-available/webdav.conf
server {
    listen 80;
    # mkdir -p /var/www/tmp/client_temp && chown nobody:nobody /var/www -R
    # curl --upload-file bigfile.iso http://localhost/upload/file1
    location /upload {
        client_max_body_size 10000m;
        # root /var/www;
        alias /var/www;
        client_body_temp_path /var/www/tmp/client_temp;
        dav_methods  PUT DELETE MKCOL COPY MOVE;
        create_full_put_path   on;
        dav_access             group:rw  all:r;
        # limit_except GET {
        #     allow 192.168.168.0/24;
        #     deny all;
        # }
    }
    # sec=3600
    # expire=$(date -d "+${sec} second" +%s)
    # method=GET/PUT
    # echo -n "prekey${expire}/store/file.txt${method}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =
    # curl --upload-file bigfile.iso "http://${srv}/store/file.txt?k=XXXXXXXXXXXXXX&e=${expire}"
    # curl http://${srv}/store/file.txt?k=XXXXXXXXXXXXXX&e=${expire}
    location /store {
        set $mykey prekey;
        if ($request_method !~ ^(PUT|GET)$ ) {
            return 444 "444 METHOD(PUT/GET)";
        }
        if ($request_method = GET) {
            set $mykey getkey;
        }
        alias /var/www;
        secure_link $arg_k,$arg_e;
        secure_link_md5 "$mykey$secure_link_expires$uri$request_method";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
        client_max_body_size 10000m;
        client_body_temp_path /var/www/tmp/client_temp;
        # root /var/www;
        dav_methods  PUT DELETE MKCOL COPY MOVE;
        create_full_put_path   on;
        dav_access             group:rw  all:r;
        # limit_except GET {
        #     allow 192.168.168.0/24;
        #     deny all;
        # }
    }
}
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/http-available/memory_cached.conf
server {
    location / {
        set            $memcached_key "$uri?$args";
        memcached_pass host:11211;
        error_page     404 502 504 = @fallback;
    }
    location @fallback {
        proxy_pass     http://backend;
    }
}
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/http-available/split_client.conf
split_clients "${remote_addr}" $variant {
    0.5%               .one;
    2.0%               .two;
    *                  "";
}
server {
    location / {
        index index${variant}.html;
        root /var/www;
    }
}
EOF
cat <<'EOF'
location / {
    sub_filter '</body>' '<a href="http://www.xxxx.com"><img style="position: fixed; top: 0; right: 0; border: 0;" src="https://res.xxxx.com/_static_/demo.png" alt="bj idc"></a></body>';
    proxy_set_header referer http://www.xxx.net; #如果网站有验证码，可以解决验证码不显示问题
    sub_filter_once on;
    sub_filter_types text/html;
}
...........................
sub_filter '</body>' '<a href="http://xxxx"><img style="position: fixed; top: 0; right: 0; border: 0;" sr    c="http://s3.amazonaws.com/github/ribbons/forkme_right_gray_6d6d6d.png" alt="xxxxxxxxxxxx"></a></body>';
sub_filter '</head>' '<link rel="stylesheet" type="text/css" href="/fuck/gray.css"/></head>';
sub_filter_once on;
...........................
HTML {
filter: grayscale(100%);
-webkit-filter: grayscale(100%);
-moz-filter: grayscale(100%);
-ms-filter: grayscale(100%);
-o-filter: grayscale(100%);
filter: url(desaturate.svg#grayscale);
filter:progid:DXImageTransform.Microsoft.BasicImage(grayscale=1);
-webkit-filter: grayscale(1);
}
............................
EOF

cat <<'EOF' > ${OUTDIR}/etc/nginx/nginx.conf
user nginx nginx;
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

# apt install rpm ruby-rubygems
# gem install fpm
# echo "getent group nginx >/dev/null || groupadd --system nginx || :" > /tmp/inst.sh
# echo "getent passwd nginx >/dev/null || useradd -g nginx --system -s /sbin/nologin -d /var/empty/nginx nginx 2> /dev/null || :" > /tmp/uninst.sh
# fpm -s dir -t rpm -C ${OUTDIR} --name nginx_xikang --version 1.20.1 --iteration 1 --description "xikang nginx with openssl,other modules" --after-install /tmp/inst.sh --after-remove /tmp/uninst.sh .

#rpm -qp --scripts  openssh-server-8.0p1-10.el8.x86_64.rpm
