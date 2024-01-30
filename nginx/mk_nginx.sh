#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("f98fef1[2023-11-15T16:54:01+08:00]:mk_nginx.sh")
set -o errtrace
set -o nounset
set -o errexit
declare -A stage=(
    [doall]=100
    [fpm]=10
    [install]=20
    [make]=30
    [configure]=40
    [openssl]=60
)
set +o nounset
stage_level=${stage[${1:-doall}]}
set -o nounset
mydesc=""
##OPTION_START##
## openssl 3.0 disabled TLSv1.0/1.1(even ssl_protocols TLSv1 TLSv1.1 TLSv1.2;)
## openssl 1.xx TLS1.0/1.1 OK
NGX_USER=${NGX_USER:-nginx}
NGX_GROUP=${NGX_GROUP:-nginx}
NGINX_RELEASE=${NGINX_RELEASE:-release-1.20.2}
NJS_RELEASE=${NJS_RELEASE:-0.7.0}
CC_OPTS=${CC_OPTS:-"-O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC"}
LD_OPTS=${LD_OPTS:-"-Wl,-z,relro -Wl,-z,now -fPIC"}
# Performance Improvement with kTLS, 10%
# enable ktls, --with-openssl=/openssl-3.0.0 --with-openssl-opt=enable-ktls
# kTLS, need kernel > 4.17(best 5.10 with CONFIG_TLS=m/y, Ubuntu 21.04) & openssl > 3.0.0 & nginx > 1.21.4
# add: ssl_conf_command Options KTLS; ssl_protocols TLSv1.3;
# To verify that NGINX is using kTLS, enable debugging mode
# check for BIO_get_ktls_send() and SSL_sendfile() in the error log
# error_log /var/log/nginx/error.log debug;
KTLS=${KTLS:-""}
STRIP=${STRIP:-""}
PKG=${PKG:-""}
# modules selection default NO select, http2_chunk_size 128k, when ktls performance good than 8k
HTTP2=${HTTP2:-""}
HTTP3=${HTTP3:-""}
STREAM_QUIC=${STREAM_QUIC:-""}
#patch need
PROXY_CONNECT=${PROXY_CONNECT:-""}
#static module
LIMIT_SPEED=${LIMIT_SPEED:-""}
CACHE_PURGE=${CACHE_PURGE:-""}
#dynamic module
AUTH_LDAP=${AUTH_LDAP:-""}
IMAGE_FILTER=${IMAGE_FILTER:-""}
PAGE_SPEED=${PAGE_SPEED:-""}
HEADER_MORE=${HEADER_MORE:-""}
REDIS=${REDIS:-""}
VTS=${VTS:-""}
##OPTION_END##
log() {
    echo "$(tput setaf 141)$*$(tput sgr0)" >&2
}
cat <<EOF
1. https://github.com/nginx-modules
2. for QUIC: use boringssl/openssl-quic
    git clone https://github.com/google/boringssl
    git clone https://github.com/quictls/openssl
EOF
NGINX_DIR=${DIRNAME}/nginx
OPENSSL_DIR=${DIRNAME}/openssl
PCRE_DIR=${DIRNAME}/pcre  #latest version pcre 8.45, pcre2 support nginx 1.21.5+
ZLIB_DIR=${DIRNAME}/zlib
declare -A NGINX_BASE=(
    [${NGINX_DIR}]="git clone --depth 1 --branch ${NGINX_RELEASE} https://github.com/nginx/nginx.git"
    [${OPENSSL_DIR}]="wget --no-check-certificate -O openssl.tar.gz https://www.openssl.org/source/openssl-1.1.1m.tar.gz || https://github.com/quictls/openssl || https://www.openssl.org/source/openssl-3.1.0.tar.gz"
    [${PCRE_DIR}]="wget --no-check-certificate -O pcre.tar.gz https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz/download || https://sourceforge.net/projects/pcre/files/pcre2/10.37/pcre2-10.37.zip/download"
    [${ZLIB_DIR}]="wget --no-check-certificate -O zlib.tar.gz https://zlib.net/zlib-1.2.11.tar.gz"
)
declare -A DYNAMIC_MODULES=(
    [${DIRNAME}/njs/nginx]="git clone --depth 1 --branch ${NJS_RELEASE} https://github.com/nginx/njs.git"
    [${DIRNAME}/nginx-rtmp-module]="git clone --depth 1 https://github.com/arut/nginx-rtmp-module.git"
    [${DIRNAME}/ngx_brotli]="git clone --depth 1 --recursive https://github.com/google/ngx_brotli.git"
    # [${DIRNAME}/nginx-influxdb-module]="http://github.com/influxdata/nginx-influxdb-module.git"
    # [${DIRNAME}/ngx_http_auth_pam_module]="git clone --depth 1 https://github.com/sto/ngx_http_auth_pam_module.git"
    # [${DIRNAME}/NginxExecute]="git clone --depth 1 https://github.com/limithit/NginxExecute.git"
    # [${DIRNAME}/Nginx-DOH-Module]="git clone --depth 1 https://github.com/dvershinin/Nginx-DOH-Module.git"
    # [${DIRNAME}/ModSecurity-nginx]="git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git"
)
declare -A STATIC_MODULES=(
    [${DIRNAME}/nginx-sticky-module-ng]="git clone --depth 1 https://bitbucket.org/nginx-goodies/nginx-sticky-module-ng"
)
[ -z "${LIMIT_SPEED}" ] || {
    STATIC_MODULES[${DIRNAME}/nginx_limit_speed_module]="git clone --depth 1 https://github.com/yaoweibin/nginx_limit_speed_module.git"
}
[ -z "${CACHE_PURGE}" ] || {
    STATIC_MODULES[${DIRNAME}/ngx_cache_purge]="git clone --depth 1 https://github.com/FRiCKLE/ngx_cache_purge.git"
}
[ -z "${PROXY_CONNECT}" ] || {
    log "pushd $(pwd) && cd ${NGINX_DIR} && git apply ${DIRNAME}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_1018.patch && popd"
    DYNAMIC_MODULES[${DIRNAME}/ngx_http_proxy_connect_module]="git clone --depth 1 https://github.com/chobits/ngx_http_proxy_connect_module.git"
}
[ -z "${AUTH_LDAP}" ] || {
    DYNAMIC_MODULES[${DIRNAME}/nginx-auth-ldap]="git clone https://github.com/kvspb/nginx-auth-ldap.git"
}
[ -z "${PAGE_SPEED}" ] || {
    DYNAMIC_MODULES[${DIRNAME}/incubator-pagespeed-ngx]="git clone --depth 1 --branch latest-stable https://github.com/apache/incubator-pagespeed-ngx.git"
}
[ -z "${HEADER_MORE}" ] || {
    DYNAMIC_MODULES[${DIRNAME}/headers-more-nginx-module]="git clone --depth 1 https://github.com/openresty/headers-more-nginx-module.git"
}
[ -z "${REDIS}" ] || {
    DYNAMIC_MODULES[${DIRNAME}/ngx_http_redis]="git clone --depth 1 https://github.com/osokin/ngx_http_redis.git"
}
[ -z "${VTS}" ] || {
    DYNAMIC_MODULES[${DIRNAME}/nginx-module-vts]="git clone --depth 1 https://github.com/vozlt/nginx-module-vts.git"
}
log "NGINX_BASE : =============================="
for key in "${!NGINX_BASE[@]}"; do
    printf '%-20.20s ==> %s\n' "${key##*/}" "${NGINX_BASE[${key}]}"
done
log "DEFAULT STATIC_MODULES : ================="
for key in "${!STATIC_MODULES[@]}"; do
    printf '%-20.20s ==> %s\n' "${key##*/}" "${STATIC_MODULES[${key}]}"
done
log "DEFAULT DYNAMIC_MODULES : ================="
for key in "${!DYNAMIC_MODULES[@]}"; do
    printf '%-20.20s ==> %s\n' "${key##*/}" "${DYNAMIC_MODULES[${key}]}"
done
sed -n '/^##OPTION_START/,/^##OPTION_END/p' ${0}
stage_level=${stage_level:?"${SCRIPTNAME} fpm/install/make/configure/openssl"}

# # proxy_connect_module
# cd nginx && git apply ${DIRNAME}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_1018.patch
# # ModSecurity Library
# git clone https://github.com/SpiderLabs/ModSecurity.git
# # ModSecurity core rules
# git clone --depth 1 --branch v3.3.2 https://github.com/coreruleset/coreruleset.git
# git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity
# cd ModSecurity || exit 1
# git submodule init
# git submodule update
# ./build.sh
# ./configure
# make -j "$(nproc)"
# make install
# mkdir /etc/nginx/modsec
# wget -P /etc/nginx/modsec/ https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended
# mv /etc/nginx/modsec/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf
# # Enable ModSecurity in Nginx
# if [[ $MODSEC_ENABLE == 'y' ]]; then
#     sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf
# fi

EXT_MODULES=(
    "--with-http_ssl_module"
    "--with-http_realip_module"
    "--with-http_addition_module"
    "--with-http_sub_module"
    "--with-http_gunzip_module"
    "--with-http_gzip_static_module"
    "--with-http_auth_request_module"
    "--with-http_secure_link_module"
    "--with-http_slice_module"
    "--with-http_stub_status_module"
    "--with-http_random_index_module"
    "--with-http_dav_module"
    "--with-http_flv_module"
    "--with-http_mp4_module"
    "--with-stream"
    "--with-stream_ssl_module"
    "--with-stream_realip_module"
    "--with-stream_ssl_preread_module"
    "--with-mail=dynamic"
    "--with-mail_ssl_module"
    "--with-http_geoip_module=dynamic"
    "--with-stream_geoip_module=dynamic"
    "--with-http_xslt_module=dynamic"
)

check_requre_dirs() {
    local dir=""
    for dir in $@ ; do
        [ -d "${dir}" ] || { log "[FAILED] ${dir} not exists!!"; exit 1; }
        log "[OK] ${dir}"
    done
}

check_depends_lib() {
    local dir=""
    for dir in $@ ; do
        pkg-config --exists ${dir} || {
            log "[FAILED] ${dir} not exists!!"
            log "apt -y install libxml2-dev libxslt1-dev libgeoip-dev libgd-dev libldap2-dev uuid-dev"
            log "yum -y install libxml2-devel libxslt-devel GeoIP-devel gd-devel openldap-devel uuid-devel"
            log "yum -y install rpm-build"
            exit 1
        }
        log "[OK] ${dir}"
    done
}

[ -z "${KTLS}" ] || { mydesc="${mydesc:+${mydesc},}ktls"; }
[ -z "${HTTP2}" ] || { mydesc="${mydesc:+${mydesc},}http2"; EXT_MODULES+=("--with-http_v2_module"); }
[ -z "${HTTP3}" ] || { mydesc="${mydesc:+${mydesc},}http3"; EXT_MODULES+=("--with-http_v3_module"); }
[ -z "${STREAM_QUIC}" ] || { mydesc="${mydesc:+${mydesc},}stream_quic"; EXT_MODULES+=("--with-stream_quic_module"); }
[ -z "${IMAGE_FILTER}" ] || { EXT_MODULES+=("--with-http_image_filter_module=dynamic"); check_depends_lib gdlib; }

check_depends_lib libxml-2.0 libxslt geoip #uuid

:<<'EOF'
# git clone --depth 1 https://github.com/nginx/njs-examples.git
# git clone https://github.com/google/ngx_brotli.git && cd ngx_brotli && git submodule update --init
# git clone https://github.com/mdirolf/nginx-gridfs.git && cd nginx-gridfs && git submodule update --init
# eval coredump
# git clone --depth 1 https://github.com/vkholodkov/nginx-eval-module.git
    http_xslt_module needs libxml2-dev libxslt1-dev / libxml2-devel libxslt-devel
    http_geoip_module needs libgeoip-dev / GeoIP-devel
    http_image_filter needs libgd-dev / gd-devel
    nginx-auth-ldap needs libldap2-dev / openldap-devel
    pagespeed needs uuid-dev
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

log "ALL ENABLED REPO : =============================="
printf '%s\n' "${NGINX_BASE[@]}" "${STATIC_MODULES[@]}" "${DYNAMIC_MODULES[@]}"
check_requre_dirs "${!NGINX_BASE[@]}" "${!STATIC_MODULES[@]}" "${!DYNAMIC_MODULES[@]}"

pcre_version=$(${PCRE_DIR}/configure -V | grep PCRE | awk '{ print $1, $3 }')
zlib_version=$(grep "Changes in" ${ZLIB_DIR}/ChangeLog  | head -1 | awk '{ print $3 }')
builder_version=$(echo "${VERSION[@]}" | cut -d'[' -f 1)
log "${builder_version}, $pcre_version, zlib ${zlib_version}"

[ ${stage_level} -ge ${stage[openssl]} ] && cd ${OPENSSL_DIR} && ./config --prefix=${OPENSSL_DIR}/.openssl no-shared no-threads ${KTLS:+enable-ktls} \
    && make -j "$(nproc)" build_libs && make -j "$(nproc)" install_sw LIBDIR=lib

export NJS_CC_OPT="-L${OPENSSL_DIR}/.openssl/lib"

for mod in "${!STATIC_MODULES[@]}"; do
    EXT_MODULES+=("--add-module=${mod}")
done
for mod in "${!DYNAMIC_MODULES[@]}"; do
    EXT_MODULES+=("--add-dynamic-module=${mod}")
done

cd ${NGINX_DIR} && ln -s auto/configure 2>/dev/null || true
[ ${stage_level} -ge ${stage[configure]} ] && cd ${NGINX_DIR} && ./configure --prefix=/usr/share/nginx \
--user=nginx \
--group=nginx \
--with-cc-opt="${CC_OPTS} -I${OPENSSL_DIR}/.openssl/include" \
--with-ld-opt="${LD_OPTS} -L${OPENSSL_DIR}/.openssl/lib" \
--with-pcre=${PCRE_DIR} \
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
${KTLS:+--with-debug} \
 \
--with-compat \
 \
--with-zlib=${ZLIB_DIR} \
 \
${EXT_MODULES[@]}

sed -i "s/NGX_CONFIGURE\s*.*$/NGX_CONFIGURE \"builder ${builder_version},${pcre_version},zlib ${zlib_version},${mydesc}\"/g" ${NGINX_DIR}/objs/ngx_auto_config.h 2>/dev/null || true
[ ${stage_level} -ge ${stage[make]} ] && cd ${NGINX_DIR} && make -j "$(nproc)"
OUTDIR=${DIRNAME}/out
mkdir -p ${OUTDIR}
[ ${stage_level} -ge ${stage[install]} ] && rm -rf ${OUTDIR}/* && cd ${NGINX_DIR} && make -j "$(nproc)" install DESTDIR=${OUTDIR}

log "/usr/lib/tmpfiles.d/nginx.conf"
mkdir -p ${OUTDIR}/usr/lib/tmpfiles.d/
cat <<'EOF' > ${OUTDIR}/usr/lib/tmpfiles.d/nginx.conf
d /var/lib/nginx 0755 root root -
d /var/log/nginx 0755 root root -
EOF
log "/usr/lib/systemd/system/nginx.service"
mkdir -p ${OUTDIR}/usr/lib/systemd/system/
cat <<'EOF' > ${OUTDIR}/usr/lib/systemd/system/nginx.service
[Unit]
Description=The nginx HTTP and reverse proxy server
After=network.target remote-fs.target nss-lookup.target

[Service]
EnvironmentFile=-/etc/default/nginx
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

log "/etc/logrotate.d/nginx"
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
mkdir -p ${OUTDIR}/var/lib/nginx/body
mkdir -p ${OUTDIR}/var/lib/nginx/proxy
mkdir -p ${OUTDIR}/var/lib/nginx/fastcfg
mkdir -p ${OUTDIR}/var/lib/nginx/uwsgi
mkdir -p ${OUTDIR}/var/lib/nginx/scgi

cat <<'EOF' > ${OUTDIR}/etc/nginx/http-conf.d/server.conf
server_names_hash_max_size 1024;
client_max_body_size 100M;
client_body_buffer_size 128k;
client_header_buffer_size 32k;
large_client_header_buffers 4 64k;
EOF

cat <<'EOF' > ${OUTDIR}/etc/nginx/http-conf.d/gzip-compress.conf
gzip on;
gunzip on;
gzip_static on;
gzip_buffers 16 8k;
gzip_comp_level 6;
gzip_http_version 1.1;
gzip_min_length 256;
gzip_proxied any;
# # maybe multi vary on response
# gzip_vary on;
gzip_disable "msie6";
gzip_types
    application/atom+xml
    application/geo+json
    application/javascript
    application/x-javascript
    application/json
    application/ld+json
    application/manifest+json
    application/rdf+xml
    application/rss+xml
    application/vnd.ms-fontobject
    application/wasm
    application/x-web-app-manifest+json
    application/xhtml+xml
    application/xml
    font/eot
    font/otf
    font/ttf
    image/bmp
    image/svg+xml
    text/cache-manifest
    text/calendar
    text/css
    text/javascript
    text/markdown
    text/plain
    text/xml
    text/vcard
    text/vnd.rim.location.xloc
    text/vtt
    text/x-component
    text/x-cross-domain-policy;
EOF

cat <<'EOF' > ${OUTDIR}/etc/nginx/http-conf.d/proxy.conf
proxy_redirect off;
proxy_pass_header Server;
proxy_pass_header Set-Cookie;
proxy_connect_timeout 3s;
proxy_read_timeout 60s;
proxy_send_timeout 60s;
proxy_intercept_errors on;
proxy_next_upstream error timeout invalid_header;
# # if http-enabled config has proxy_set_header, need add below too!!!
# # These directives are inherited from the previous configuration level
# # if and only if there are no proxy_set_header directives defined on the current level
proxy_set_header Host $host;
proxy_set_header Connection "";
proxy_http_version 1.1;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Real-IP $remote_addr;
# # for no use gzip.
proxy_set_header Accept-Encoding "";

proxy_request_buffering on;
# # limiting bandwidth speed in proxy and cache responses not work, if proxy_buffering is set to off.
proxy_buffering on;
proxy_buffer_size 8k;
proxy_buffers 128 8k;
proxy_busy_buffers_size 128k;
# # zero value disables buffering of responses to temporary files.
proxy_max_temp_file_size 0;
proxy_headers_hash_bucket_size 10240;
proxy_headers_hash_max_size 102400;
proxy_ignore_client_abort on;
EOF

cat <<'EOF' > ${OUTDIR}/etc/nginx/http-conf.d/httplog.conf
open_log_file_cache max=100 inactive=10m min_uses=1 valid=60s;
# log_subrequest on;

log_format json escape=json '{ "node": "$hostname", "scheme":"$scheme", "http_host": "$http_host", "server_port": $server_port, "upstream_addr": "$upstream_addr",'
    '"request_time": $request_time, "upstream_response_time":"$upstream_response_time", "upstream_status": "$upstream_status",'
    '"remote_addr": "$remote_addr", "remote_user": "$remote_user", "time_iso8601": "$time_iso8601", "request": "$request",'
    '"status": $status,"request_length": $request_length, "bytes_sent": $bytes_sent, "http_referer": "$http_referer",'
    '"http_user_agent": "$http_user_agent", "http_x_forwarded_for": "$http_x_forwarded_for", "gzip_ratio": "$gzip_ratio",'
    '"upstream_cache_status":"$upstream_cache_status" }';

log_format main '$hostname $scheme $http_host $server_port "$upstream_addr" '
    '[$request_time|"$upstream_response_time"|"$upstream_status"] '
    '$remote_addr - $remote_user [$time_iso8601] "$request" '
    '$status $request_length $bytes_sent "$http_referer" '
    '"$http_user_agent" "$http_x_forwarded_for" "$upstream_cache_status" $gzip_ratio';
    #$brotli_ratio

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

# # access log
# default buffer size is equal to 64K bytes
access_log /var/log/nginx/access_err.log json buffer=512k flush=5m if=$log_err;
access_log /var/log/nginx/access.log main buffer=512k flush=5m if=$log_ip;
# access_log /var/log/nginx/$http_host-access.log buffer=512k flush=5m;
# access_log /var/log/nginx/access_$status.log

# # error log
error_log /var/log/nginx/error.log info;
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/stream-conf.d/streamlog.conf
log_format basic '$protocol $server_port $ssl_preread_server_name "$upstream_addr" '
    '[$time_iso8601] $remote_addr $status $bytes_sent $bytes_received $session_time';
access_log /var/log/nginx/stream_access.log basic buffer=512k flush=5m;
error_log /var/log/nginx/stream_error.log info;
EOF
mkdir -p ${OUTDIR}/etc/nginx/modules.d/
cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/brotli.conf
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/js.conf
# load_module modules/ngx_http_js_module.so;
# load_module modules/ngx_stream_js_module.so;
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/geoip.conf
# load_module modules/ngx_http_geoip_module.so;
# load_module modules/ngx_stream_geoip_module.so;
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/rtmp.conf
# load_module modules/ngx_rtmp_module.so;
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/redis.conf
# load_module modules/ngx_http_redis_module.so;
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/mail.conf
# load_module modules/ngx_mail_module.so;
EOF
cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/xslt.conf
# load_module modules/ngx_http_xslt_filter_module.so;
EOF
[ -z "${VTS}" ] || cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/traffic_status.conf
# load_module modules/ngx_http_vhost_traffic_status_module.so;
EOF
[ -z "${HEADER_MORE}" ] || cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/headers_more.conf
# load_module modules/ngx_http_headers_more_filter_module.so;
EOF
[ -z "${PROXY_CONNECT}" ] || cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/proxy_connect.conf
# load_module modules/ngx_http_proxy_connect_module.so;
EOF
[ -z "${IMAGE_FILTER}" ] || cat <<'EOF' > ${OUTDIR}/etc/nginx/modules.d/http_image_filter.conf
# load_module modules/ngx_http_image_filter_module.so;
EOF

cat <<EOF > ${OUTDIR}/etc/nginx/nginx.conf
user ${NGX_USER} ${NGX_GROUP};
worker_processes auto;
worker_rlimit_nofile 1024000;
worker_priority -20;
pcre_jit on;
pid /run/nginx.pid;
include /etc/nginx/modules.d/*.conf;
events {
    use epoll;
    worker_connections 409600;
    multi_accept on;
}
http {
    sendfile on;
    sendfile_max_chunk 2048k;

    tcp_nopush on;
    tcp_nodelay on;
    types_hash_max_size 2048;
    server_tokens off;

    # # thread pool
    aio threads=default;

    # # allow the server to close connection on non responding client, this will free up memory
    reset_timedout_connection on;

    # # number of requests client can make over keep-alive
    keepalive_requests 86400;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # # SSL
${KTLS:+    ssl_conf_command Options KTLS;}
    ssl_protocols TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE, drop TLSv1 TLSv1.1
    ssl_prefer_server_ciphers on;
${HTTP2:+    http2_chunk_size 128k;}
    # # vhost include
    include /etc/nginx/http-conf.d/*.conf;
    include /etc/nginx/http-enabled/*.conf;
}

stream {
    include /etc/nginx/stream-conf.d/*.conf;
    include /etc/nginx/stream-enabled/*.conf;
}
EOF
rm -f  ${OUTDIR}/etc/nginx/*.default || true
chmod 644 ${OUTDIR}/usr/share/nginx/modules/* || true
[ -z "${STRIP}" ] || {
    log "strip binarys"
    strip ${OUTDIR}/usr/sbin/nginx
    strip ${OUTDIR}/usr/share/nginx/modules/*
}

command -v "fpm" &> /dev/null || {
    cat <<EOF
apt -y install rpm ruby-rubygems || yum -y install rubygems
gem source -l
gem sources -a http://mirrors.aliyun.com/rubygems/
gem sources --remove https://rubygems.org/
gem install fpm
# gem install --http-proxy http://user:pass@proxysrv:port fpm
EOF
    echo "NO PACKAGE TOOLS"
    exit 1
}
echo "getent group ${NGX_GROUP} >/dev/null || groupadd --system ${NGX_GROUP} || :" > /tmp/inst.sh
echo "getent passwd ${NGX_USER} >/dev/null || useradd -g ${NGX_GROUP} --system -s /sbin/nologin -d /var/empty/nginx ${NGX_USER} 2> /dev/null || :" >> /tmp/inst.sh
echo "userdel nginx || :" > /tmp/uninst.sh
rm -fr ${DIRNAME}/pkg && mkdir -p ${DIRNAME}/pkg

source <(grep -E "^\s*(VERSION_ID|ID)=" /etc/os-release)
case "${ID}" in
    ########################################
    centos)  PKG=${PKG:-rpm};;
    openEuler)  PKG=${PKG:-rpm};;
    debian)  PKG=${PKG:-deb};;
    *)       log "ALL DONE, NO PACKAGE"; exit 0;;
esac
eval NGX_VER=$(awk '/NGINX_VERSION / {print $3}' ${NGINX_DIR}/src/core/nginx.h)
log "NGINX:${NGX_VER}"
log "BUILD:${builder_version}"
[ ${stage_level} -ge ${stage[fpm]} ] && fpm --package ${DIRNAME}/pkg -s dir -t ${PKG} -C ${OUTDIR} --name nginx_johnyin${HTTP3:+_quic} --version $(echo ${NGX_VER}) --iteration ${builder_version} --description "nginx with openssl,other modules" --after-install /tmp/inst.sh --after-remove /tmp/uninst.sh .
log "ALL PACKAGE OUT: ${DIRNAME}/pkg for ${ID}-${VERSION_ID} ${PKG}"
#rpm -qp --scripts  openssh-server-8.0p1-10.el8.x86_64.rpm
