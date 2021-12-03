#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("b27277c[2021-12-03T12:04:38+08:00]:mk_nginx.sh")
set -o errtrace
set -o nounset
set -o errexit
cat <<EOF
ZLIB       git clone --depth 1 https://github.com/cloudflare/zlib
PCRE       https://www.pcre.org
OPENSSL    https://www.openssl.org/source/
nginx-eval-module-master https://github.com/anomalizer/ngx_aws_auth
https://github.com/kaltura/nginx-aws-auth-module
git clone https://github.com/nginx/njs-examples.git
EOF
:<<"EOF"
for SM2 ssl replace:
--with-openssl=${DIRNAME}/wotrus_ssl2.0

auto/lib/openssl/conf
 39             CORE_INCS="$CORE_INCS $OPENSSL/include"
 40             CORE_DEPS="$CORE_DEPS $OPENSSL/include/openssl/ssl.h"
 41             CORE_LIBS="$CORE_LIBS $OPENSSL/lib/libssl.a"
 42             CORE_LIBS="$CORE_LIBS $OPENSSL/lib/libcrypto.a"
EOF

OPENSSL_DIR=${DIRNAME}/openssl-1.1.1l
ZLIB_DIR=${DIRNAME}/zlib-1.2.11.dfsg
PCRE_DIR=${DIRNAME}/pcre-8.39

cd ${OPENSSL_DIR} && ./config --prefix=${OPENSSL_DIR}/.openssl no-shared no-threads \
    && make build_libs && make install_sw LIBDIR=lib

cd ${PCRE_DIR} && CC="cc" CFLAGS="-O2 -fomit-frame-pointer -pipe "  \
    ./configure --disable-shared --enable-jit \
    --libdir=${PCRE_DIR}/.libs/ --includedir=${PCRE_DIR} && \
    make
# njs configure need expect
# expect -v || sudo apt install expect
echo "http_xslt_module needs libxml2-dev libxslt1-dev"

# for njs pcre-config command!
export PATH=$PATH:${PCRE_DIR}
export NJS_CC_OPT="-L${OPENSSL_DIR}/.openssl/lib"
echo "PCRE OK **************************************************"
cd ${DIRNAME} && ./configure --prefix=/usr/share/nginx \
--user=nginx \
--group=nginx \
--with-cc-opt="$(pcre-config --cflags) -I${OPENSSL_DIR}/.openssl/include" \
--with-ld-opt="$(pcre-config --libs) -L${OPENSSL_DIR}/.openssl/lib" \
--with-pcre \
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
--with-debug \
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
--with-zlib=${ZLIB_DIR} \
 \
--with-http_geoip_module=dynamic \
--with-stream_geoip_module=dynamic \
--with-http_xslt_module=dynamic \
--add-dynamic-module=njs/nginx \
 \
--add-module=nginx-goodies-nginx-sticky-module-ng-08a395c66e42 \
--add-module=nginx_limit_speed_module-master \
--add-module=nginx-module-vts-master \
--add-module=ngx_http_redis-0.3.9 \
--add-module=nginx-eval-module-master \
--add-module=nginx-rtmp-module-1.2.2

TMP_VER=$(echo "${VERSION[@]}" | sed "s/${SCRIPTNAME}/by johnyin/g")
echo "${TMP_VER}**************************************************"
sed -i "s/NGX_CONFIGURE\s*.*$/NGX_CONFIGURE \"${TMP_VER}\"/g" ${DIRNAME}/objs/ngx_auto_config.h
cd ${DIRNAME} && make
OUTDIR=${DIRNAME}/out
rm -rf ${OUTDIR}
mkdir -p ${OUTDIR}
cd ${DIRNAME} && make install DESTDIR=${OUTDIR}

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
log_format main '$scheme $http_host $server_port [$request_time|$upstream_response_time|$upstream_status] '
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

cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.conf
# load_module modules/ngx_http_geoip_module.so;
# load_module modules/ngx_http_js_module.so;
# load_module modules/ngx_http_xslt_filter_module.so;
# load_module modules/ngx_stream_geoip_module.so;
# load_module modules/ngx_stream_js_module.so;
EOF

cat <<'EOF' > ${OUTDIR}/etc/nginx/nginx.conf
user nginx nginx;
worker_processes auto;
worker_rlimit_nofile 102400;
pid /run/nginx.pid;
include /etc/nginx/modules.conf;
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

    # # vhost include
    include /etc/nginx/http-conf.d/*.conf;
    include /etc/nginx/http-enabled/*;
}

stream {
    include /etc/nginx/stream-conf.d/*.conf;
    include /etc/nginx/stream-enabled/*;
}
EOF
rm -f  ${OUTDIR}/etc/nginx/*.default
chmod 644 ${OUTDIR}/usr/share/nginx/modules/*

# apt install rpm ruby-rubygems
# gem install fpm
echo "getent group nginx >/dev/null || groupadd --system nginx || :" > /tmp/inst.sh
echo "getent passwd nginx >/dev/null || useradd -g nginx --system -s /sbin/nologin -d /var/empty/nginx nginx 2> /dev/null || :" > /tmp/uninst.sh
rm -fr ${DIRNAME}/pkg && mkdir -p ${DIRNAME}/pkg
fpm --package ${DIRNAME}/pkg -s dir -t deb -C ${OUTDIR} --name nginx_johnyin --version 1.20.1 --iteration 1 --description "nginx with openssl,other modules" --after-install /tmp/inst.sh --after-remove /tmp/uninst.sh .
fpm --package ${DIRNAME}/pkg -s dir -t rpm -C ${OUTDIR} --name nginx_johnyin --version 1.20.1 --iteration 1 --description "nginx with openssl,other modules" --after-install /tmp/inst.sh --after-remove /tmp/uninst.sh .
echo "ALL PACKAGE OUT: ${DIRNAME}/pkg"
#rpm -qp --scripts  openssh-server-8.0p1-10.el8.x86_64.rpm
