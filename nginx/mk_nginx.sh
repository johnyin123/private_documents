#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("3db7018f[2024-11-22T14:05:57+08:00]:mk_nginx.sh")
set -o errtrace
set -o nounset
set -o errexit
declare -A stage=(
    [doall]=100
    [fpm]=10
    [install]=20
    [make]=30
    [configure]=40
    [otherlibs]=50
    [openssl]=60
    [pcre]=70
    [zlib]=80
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
CC_OPTS=${CC_OPTS:-"-O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC"}
LD_OPTS=${LD_OPTS:-"-Wl,-z,relro -Wl,-z,now -fPIC"}
# Performance Improvement with kTLS, 10%
# enable ktls, --with-openssl=/openssl-3.0.0 --with-openssl-opt=enable-ktls
# kTLS, need kernel > 4.17(best 5.10 with CONFIG_TLS=m/y, Ubuntu 21.04) & openssl > 3.0.0 & nginx > 1.21.4
# add: ssl_conf_command Options KTLS; ssl_protocols TLSv1.3;
# To verify that NGINX is using kTLS, enable debugging mode
# check for BIO_get_ktls_send() and SSL_sendfile() in the error log
# error_log /var/log/nginx/error.log debug;
KTLS=${KTLS-"1"}
STRIP=${STRIP-"1"}
PKG=${PKG:-""}
# modules selection default NO select, http2_chunk_size 128k, when ktls performance good than 8k
HTTP2=${HTTP2-"1"}
HTTP3=${HTTP3:-""}
STREAM_QUIC=${STREAM_QUIC:-""}
#patch need
PROXY_CONNECT=${PROXY_CONNECT-"1"}
#static module
LIMIT_SPEED=${LIMIT_SPEED:-""}
CACHE_PURGE=${CACHE_PURGE:-""}
#dynamic module
AUTH_JWT=${AUTH_JWT-"1"}
AUTH_LDAP=${AUTH_LDAP-"1"}
IMAGE_FILTER=${IMAGE_FILTER-"1"}
PAGE_SPEED=${PAGE_SPEED:-""}
HEADER_MORE=${HEADER_MORE:-""}
REDIS=${REDIS:-""}
VTS=${VTS:-""}
CONCAT=${CONCAT-"1"}
SQLITE=${SQLITE-"1"}
AWS_AUTH=${AWS_AUTH-"1"}
##OPTION_END##
show_option() {
    local file="${1}"
    sed -n '/^##OPTION_START/,/^##OPTION_END/p' ${file} | while IFS= read -r line; do
        [[ ${line} =~ ^\ *#.*$ ]] && continue #skip comment line
        [[ ${line} =~ ^\ *$ ]] && continue #skip blank
        eval "printf '%-16.16s = %s\n' \"${line%%=*}\" \"\${${line%%=*}:-UNSET}\""
    done
}
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
opt_enable() { [ "1" == "${1:-y}" ]; }
usage() {
    echo ""
    echo "no need -lz, static build sqlite3"
    echo "stage: [${!stage[@]}]"
    echo "LD_OPTS='/usr/lib/x86_64-linux-gnu/libsqlite3.a -lm' ${SCRIPTNAME} fpm/install/make/configure/otherlibs/openssl/pcre/zlib"
    echo 'configure --with-cc-opt="-static -static-libgcc" --with-ld-opt="-static" --with-cpu-opt=generic  --with-openssl=./openssl ......'
    echo "remove --with-http_xslt_module"
    echo "remove --with-http_image_filter_module"
    echo "remove --with-http_geoip_module"
    echo "CC_OPTS='-static -static-libgcc' LD_OPTS='-static' ./configure ..... && make, will static build"
    show_option "${SCRIPTNAME}"
    exit 0
}
check_requre_dirs() {
    local dir=""
    for dir in $@ ; do
        [ -d "${dir}" ] || { log "[FAILED] ${dir} not exists!!"; exit 1; }
        log "[OK] ${dir}"
    done
}
write_file() {
    local file=${1:-}
    local append=${2:-}
    [ -z "${file}" ] || mkdir -p $(dirname ${file})
    log "[INFO] Writing ${append:+append }${file:-/dev/stdout}"
    eval cat ${file:+\>${append:+\>} ${file}}
}
check_depends_lib() {
    local dir=""
    for dir in $@ ; do
        pkg-config --exists ${dir} || {
            log "[FAILED] ${dir} not exists!!"
            log "apt -y install libxml2-dev libxslt1-dev libgeoip-dev libgd-dev libldap2-dev uuid-dev libsqlite3-dev libbrotli-dev"
            log "yum -y install libxml2-devel libxslt-devel GeoIP-devel gd-devel openldap-devel uuid-devel sqlite-devel brotli-devel"
            log "yum -y install rpm-build"
            exit 1
        }
        log "[OK] ${dir}"
    done
}
prompt() {
    local var="${1}"
    local msg="${2}"
    local tmout=${3:-}
    local nchars=${4:-}
    local value=""
    {
        trap "exit -1" SIGINT SIGTERM
        read ${nchars:+-n ${nchars}} ${tmout:+-t ${tmout}} -p "${msg}" value || true
        value="${value//\"/\'}";
    } 2>&1
    if [ ! -z "${value}" ]; then
        eval "${var}"=\"${value}\"
    fi
    echo ""
}
confirm() {
    local msg=${1:-confirm}
    local tmout=${2:-5}
    local ANSWER=""
    prompt ANSWER "${msg} [y/N] " "${tmout}" "1"
    if [ "${ANSWER}" = "Y" ] || [ "${ANSWER}" = "y" ]; then
        return 0
    fi
    return 1
}
stage_level=${stage_level:?"$(usage)"}
stage_run() {
    local level=${1}
    [ ${stage_level} -ge ${stage[${level}]} ] && {
        log "[STAGE RUN] ${level} START ................................"
        return 0
    } || return 1
}

MYLIB_DEPS=${DIRNAME}/mylibs
NGINX_DIR=${DIRNAME}/nginx
OPENSSL_DIR=${DIRNAME}/openssl
PCRE_DIR=${DIRNAME}/pcre  #latest version pcre 8.45, pcre2 support nginx 1.21.5+
ZLIB_DIR=${DIRNAME}/zlib
JANSSON_DIR=${DIRNAME}/jansson
LIBJWT_DIR=${DIRNAME}/libjwt
export NJS_CC_OPT="-L${MYLIB_DEPS}/lib"

declare -A NGINX_BASE=(
    [${NGINX_DIR}]="git clone --depth 1 --branch release-1.24.0 https://github.com/nginx/nginx.git"
    [${OPENSSL_DIR}]="https://www.openssl.org/source/openssl-1.1.1m.tar.gz || https://www.openssl.org/source/openssl-3.1.0.tar.gz"
    [${PCRE_DIR}]="https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz/download || https://sourceforge.net/projects/pcre/files/pcre2/10.37/pcre2-10.37.zip/download"
    [${ZLIB_DIR}]="https://zlib.net/zlib-1.2.11.tar.gz"
)
declare -A DYNAMIC_MODULES=(
    [${DIRNAME}/njs/nginx]="git clone --depth 1 --branch 0.8.2 https://github.com/nginx/njs.git"
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
opt_enable "${LIMIT_SPEED}" && {
    STATIC_MODULES[${DIRNAME}/nginx_limit_speed_module]="git clone --depth 1 https://github.com/yaoweibin/nginx_limit_speed_module.git"
}
opt_enable "${CACHE_PURGE}" && {
    STATIC_MODULES[${DIRNAME}/ngx_cache_purge]="git clone --depth 1 https://github.com/FRiCKLE/ngx_cache_purge.git"
}
opt_enable "${CONCAT}" && {
    STATIC_MODULES[${DIRNAME}/nginx-http-concat]="git clone https://github.com/alibaba/nginx-http-concat.git"
}
opt_enable "${SQLITE}" && {
    STATIC_MODULES[${DIRNAME}/ngx_sqlite]="git clone https://github.com/rryqszq4/ngx_sqlite.git"
}
opt_enable "${AWS_AUTH}" && {
    DYNAMIC_MODULES[${DIRNAME}/nginx-aws-auth-module]="git clone --depth 1 https://github.com/kaltura/nginx-aws-auth-module"
}
opt_enable "${PROXY_CONNECT}" && {
    log "Use PROXY CONNECT module, need patch!!!"
    log "pushd $(pwd) && cd ${NGINX_DIR} && git apply ${DIRNAME}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_1018.patch && popd"
    DYNAMIC_MODULES[${DIRNAME}/ngx_http_proxy_connect_module]="git clone --depth 1 https://github.com/chobits/ngx_http_proxy_connect_module.git"
}
opt_enable "${AUTH_JWT}" && {
    DYNAMIC_MODULES[${DIRNAME}/ngx-http-auth-jwt-module]="git clone https://github.com/TeslaGov/ngx-http-auth-jwt-module.git";
}
opt_enable "${AUTH_LDAP}" && {
    DYNAMIC_MODULES[${DIRNAME}/nginx-auth-ldap]="git clone https://github.com/kvspb/nginx-auth-ldap.git"
}
opt_enable "${PAGE_SPEED}" && {
    DYNAMIC_MODULES[${DIRNAME}/incubator-pagespeed-ngx]="git clone --depth 1 --branch latest-stable https://github.com/apache/incubator-pagespeed-ngx.git"
}
opt_enable "${HEADER_MORE}" && {
    DYNAMIC_MODULES[${DIRNAME}/headers-more-nginx-module]="git clone --depth 1 https://github.com/openresty/headers-more-nginx-module.git"
}
opt_enable "${REDIS}" && {
    DYNAMIC_MODULES[${DIRNAME}/ngx_http_redis]="git clone --depth 1 https://github.com/osokin/ngx_http_redis.git"
}
opt_enable "${VTS}" && {
    DYNAMIC_MODULES[${DIRNAME}/nginx-module-vts]="git clone --depth 1 https://github.com/vozlt/nginx-module-vts.git"
}
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
opt_enable "${KTLS}" && { mydesc="${mydesc:+${mydesc},}ktls"; }
opt_enable "${HTTP2}" && { mydesc="${mydesc:+${mydesc},}http2"; EXT_MODULES+=("--with-http_v2_module"); }
opt_enable "${HTTP3}" && { mydesc="${mydesc:+${mydesc},}http3"; EXT_MODULES+=("--with-http_v3_module"); }
opt_enable "${STREAM_QUIC}" && { mydesc="${mydesc:+${mydesc},}stream_quic"; EXT_MODULES+=("--with-stream_quic_module"); }
opt_enable "${IMAGE_FILTER}" && { EXT_MODULES+=("--with-http_image_filter_module=dynamic"); check_depends_lib gdlib; }

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
log "NGINX_BASE : =============================="
for key in "${!NGINX_BASE[@]}"; do
    printf '%-15.15s ==> %s\n' "${key##*/}" "${NGINX_BASE[${key}]}"
done
log "DEFAULT STATIC_MODULES : ================="
for key in "${!STATIC_MODULES[@]}"; do
    printf '%-15.15s ==> %s\n' "${key##*/}" "${STATIC_MODULES[${key}]}"
done
log "DEFAULT DYNAMIC_MODULES : ================="
for key in "${!DYNAMIC_MODULES[@]}"; do
    printf '%-15.15s ==> %s\n' "${key##*/}" "${DYNAMIC_MODULES[${key}]}"
done
check_requre_dirs "${!NGINX_BASE[@]}" "${!STATIC_MODULES[@]}" "${!DYNAMIC_MODULES[@]}"
pcre_version=$(${PCRE_DIR}/configure -V | grep PCRE | awk '{ print $1, $3 }')
zlib_version=$(grep "Changes in" ${ZLIB_DIR}/ChangeLog  | head -1 | awk '{ print $3 }')
builder_version=$(echo "${VERSION[@]}" | cut -d'[' -f 1)
show_option "${0}"
log "BUILD-VERSION: ${builder_version}, PCRE: $pcre_version, ZLIB: ${zlib_version}"
confirm "START BUILD NGINX(timeout 60s)?..........." 60
stage_run zlib && cd ${ZLIB_DIR} &&  ./configure --prefix=${MYLIB_DEPS} --static && make -j "$(nproc)" && make -j "$(nproc)" install
stage_run pcre && cd ${PCRE_DIR} && ./configure --prefix=${MYLIB_DEPS} --enable-jit --enable-static=yes --enable-shared=no && make -j "$(nproc)" && make -j "$(nproc)" install
stage_run openssl && cd ${OPENSSL_DIR} && ./config --prefix=${MYLIB_DEPS} no-shared no-threads ${KTLS:+enable-ktls} && make -j "$(nproc)" build_libs && make -j "$(nproc)" install_sw LIBDIR=lib
#########################otherlibs here################################
stage_run otherlibs && opt_enable "${AUTH_JWT}" && {
    log "[INFO] check jansson exist, if os not has it, download first"
    pkg-config --exists jansson && { log "[INFO] Use system jansson"; } || {
        log "[INFO] Use download jansson"
        check_requre_dirs "${JANSSON_DIR}"
        export JANSSON_CFLAGS=-I${MYLIB_DEPS}/include
        export JANSSON_LIBS=-L${MYLIB_DEPS}/lib
    # no shared lib for jansson, so jwt compile static janssonlib
        cd "${JANSSON_DIR}" && ./configure --prefix=${MYLIB_DEPS} --enable-shared=yes --enable-static=yes && make -j "$(nproc)" && make -j "$(nproc)" install
    }
    log "[INFO] check libjwt exist, if os not has it, download first"
    pkg-config --exists libjwt && { log "[INFO] Use system libjwt"; } || {
        log "[INFO] Use download libjwt"
        check_requre_dirs "${LIBJWT_DIR}"
        log "libjwt not support openssl2, so use GnuTLS, apt -y install libgnutls28-dev"
        check_depends_lib gnutls
        # OPENSSL_CFLAGS=-I${MYLIB_DEPS}/include
        # OPENSSL_LIBS=-L${MYLIB_DEPS}/lib
        cd "${LIBJWT_DIR}" && ./configure --enable-shared=yes --enable-static=yes --without-openssl --without-examples --disable-doxygen-doc --disable-doxygen-dot --disable-doxygen-man --prefix=${MYLIB_DEPS} && make -j "$(nproc)" && make -j "$(nproc)" install
    }
    CC_OPTS="${CC_OPTS} -DNGX_LINKED_LIST_COOKIES=1"
}
for mod in "${!STATIC_MODULES[@]}"; do
    EXT_MODULES+=("--add-module=${mod}")
done
for mod in "${!DYNAMIC_MODULES[@]}"; do
    EXT_MODULES+=("--add-dynamic-module=${mod}")
done

cd ${NGINX_DIR} && ln -s auto/configure 2>/dev/null || true
stage_run configure && cd ${NGINX_DIR} && ./configure --prefix=/usr/share/nginx \
--user=nginx \
--group=nginx \
--with-cc-opt="${CC_OPTS} -I${MYLIB_DEPS}/include" \
--with-ld-opt="${LD_OPTS} -L${MYLIB_DEPS}/lib" \
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
${KTLS:+--with-debug} \
 \
--with-compat \
 \
${EXT_MODULES[@]}

sed -i "s/NGX_CONFIGURE\s*.*$/NGX_CONFIGURE \"builder ${builder_version},${pcre_version},zlib ${zlib_version},${mydesc}\"/g" ${NGINX_DIR}/objs/ngx_auto_config.h 2>/dev/null || true
stage_run make && cd ${NGINX_DIR} && make -j "$(nproc)"
OUTDIR=${DIRNAME}/out
mkdir -p ${OUTDIR}

stage_run install && rm -rf ${OUTDIR}/* && cd ${NGINX_DIR} && make -j "$(nproc)" install DESTDIR=${OUTDIR} \
    && { rm -f  ${OUTDIR}/etc/nginx/*.default || true; chmod 644 ${OUTDIR}/usr/share/nginx/modules/* || true; }

write_file "${OUTDIR}/usr/lib/tmpfiles.d/nginx.conf" <<'EOF'
d /var/lib/nginx 0755 root root -
d /var/log/nginx 0755 root root -
EOF
write_file "${OUTDIR}/usr/lib/systemd/system/nginx.service" <<'EOF'
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

write_file "${OUTDIR}/etc/logrotate.d/nginx" <<'EOF'
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
mkdir -p ${OUTDIR}/etc/nginx/geoip/
mkdir -p ${OUTDIR}/etc/nginx/ssl/
mkdir -p ${OUTDIR}/var/lib/nginx/body
mkdir -p ${OUTDIR}/var/lib/nginx/proxy
mkdir -p ${OUTDIR}/var/lib/nginx/fastcfg
mkdir -p ${OUTDIR}/var/lib/nginx/uwsgi
mkdir -p ${OUTDIR}/var/lib/nginx/scgi

write_file "${OUTDIR}/etc/nginx/http-conf.d/server.conf" <<'EOF'
server_names_hash_max_size 1024;
server_names_hash_bucket_size 128;
client_max_body_size 100M;
client_body_buffer_size 128k;
client_header_buffer_size 32k;
large_client_header_buffers 4 64k;
EOF

write_file "${OUTDIR}/etc/nginx/http-conf.d/brotli-compress.conf" <<'EOF'
brotli on;
brotli_static on;
brotli_comp_level 6;
brotli_buffers 16 8k;
brotli_min_length 256;
brotli_types
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

write_file "${OUTDIR}/etc/nginx/http-conf.d/gzip-compress.conf" <<'EOF'
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

write_file "${OUTDIR}/etc/nginx/http-conf.d/proxy.conf" <<'EOF'
proxy_redirect off;
proxy_pass_header Server;
proxy_pass_header Set-Cookie;
proxy_connect_timeout 3s;
proxy_read_timeout 60s;
proxy_send_timeout 60s;
proxy_intercept_errors on;
proxy_next_upstream error timeout invalid_header;

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

# # proxy headers, if use proxy_set_header, below header will overwrite.
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Port  $server_port;
proxy_set_header Origin            $scheme://$host;
# $http_host equals always the HTTP_HOST request header.
# $host equals $http_host, lowercase and without the port number (if present),
#    except when HTTP_HOST is absent or is an empty value.
#    In that case, $host equals the value of the server_name directive
#    of the server which processed the request.
proxy_set_header Host $host;
proxy_http_version 1.1;
proxy_set_header Connection "";
# # for no use gzip.
# proxy_set_header Accept-Encoding "";
EOF

write_file "${OUTDIR}/etc/nginx/http-conf.d/httplog.conf" <<'EOF'
open_log_file_cache max=100 inactive=10m min_uses=1 valid=60s;
# log_subrequest on;

map $http_x_request_id $requestid {
    default $http_x_request_id;
    ""      $request_id;
}
proxy_set_header X-Request-ID $requestid;
add_header X-Request-ID $requestid always;

log_format json escape=json '{"node":"$hostname","scheme":"$scheme","http_host":"$http_host","server_port":$server_port,"upstream_addr":"$upstream_addr",'
    '"request_time":$request_time,"upstream_response_time":"$upstream_response_time","upstream_status":"$upstream_status",'
    '"remote_addr":"$remote_addr","remote_user":"$remote_user","time_iso8601":"$time_iso8601","request":"$request",'
    '"status":$status,"request_length":$request_length,"bytes_sent":$bytes_sent,"http_referer":"$http_referer",'
    '"http_user_agent":"$http_user_agent","http_x_forwarded_for":"$http_x_forwarded_for","requestid":"$requestid","gzip_ratio":"$gzip_ratio",'
    '"brotli_ratio":"$brotli_ratio","upstream_cache_status":"$upstream_cache_status"}';

log_format main '$hostname $scheme $http_host $server_port "$upstream_addr" '
    '[$request_time|"$upstream_response_time"|"$upstream_status"] "$requestid" '
    '$remote_addr - $remote_user [$time_iso8601] "$request" '
    '$status $request_length $bytes_sent "$http_referer" '
    '"$http_user_agent" "$http_x_forwarded_for" "$upstream_cache_status" $gzip_ratio $brotli_ratio';

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
access_log /var/log/nginx/access.log json buffer=512k flush=5m if=$log_ip;
# access_log /var/log/nginx/$http_host-access.log main buffer=512k flush=5m;
# access_log /var/log/nginx/access_$status.log main buffer=512k flush=5m;

# # error log
error_log /var/log/nginx/error.log error;
EOF
write_file "${OUTDIR}/etc/nginx/stream-conf.d/streamlog.conf" <<'EOF'
log_format basic '$remote_addr [$time_iso8601] $protocol $status $bytes_sent $bytes_received '
    '$session_time "$upstream_addr" "$upstream_bytes_sent" "$upstream_bytes_received" "$upstream_connect_time"';
access_log /var/log/nginx/stream_access.log basic buffer=512k flush=5m;
error_log /var/log/nginx/stream_error.log error;
EOF
write_file "${OUTDIR}/etc/nginx/modules.d/brotli.conf" <<'EOF'
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;
EOF
write_file "${OUTDIR}/etc/nginx/modules.d/js.conf" <<'EOF'
# load_module modules/ngx_http_js_module.so;
# load_module modules/ngx_stream_js_module.so;
EOF
write_file "${OUTDIR}/etc/nginx/modules.d/geoip.conf" <<'EOF'
# load_module modules/ngx_http_geoip_module.so;
# load_module modules/ngx_stream_geoip_module.so;
EOF
write_file "${OUTDIR}/etc/nginx/modules.d/rtmp.conf" <<'EOF'
# load_module modules/ngx_rtmp_module.so;
EOF
opt_enable "${REDIS}" && write_file "${OUTDIR}/etc/nginx/modules.d/redis.conf" <<'EOF'
# load_module modules/ngx_http_redis_module.so;
EOF
write_file "${OUTDIR}/etc/nginx/modules.d/mail.conf" <<'EOF'
# load_module modules/ngx_mail_module.so;
EOF
write_file "${OUTDIR}/etc/nginx/modules.d/xslt.conf" <<'EOF'
# load_module modules/ngx_http_xslt_filter_module.so;
EOF
opt_enable "${VTS}" && write_file "${OUTDIR}/etc/nginx/modules.d/traffic_status.conf" <<'EOF'
# load_module modules/ngx_http_vhost_traffic_status_module.so;
EOF
opt_enable "${HEADER_MORE}" && write_file "${OUTDIR}/etc/nginx/modules.d/headers_more.conf" <<'EOF'
# load_module modules/ngx_http_headers_more_filter_module.so;
EOF
opt_enable "${PROXY_CONNECT}" && write_file "${OUTDIR}/etc/nginx/modules.d/proxy_connect.conf" <<'EOF'
# load_module modules/ngx_http_proxy_connect_module.so;
EOF
opt_enable "${IMAGE_FILTER}" && write_file "${OUTDIR}/etc/nginx/modules.d/http_image_filter.conf" <<'EOF'
# load_module modules/ngx_http_image_filter_module.so;
EOF
opt_enable "${AUTH_JWT}" && write_file "${OUTDIR}/etc/nginx/modules.d/jwt.conf" <<'EOF'
# load_module modules/ngx_http_auth_jwt_module.so;
EOF
opt_enable "${AWS_AUTH}" && write_file "${OUTDIR}/etc/nginx/modules.d/aws.conf" <<'EOF'
# load_module modules/ngx_http_aws_auth_module.so;
EOF
write_file "${OUTDIR}/etc/nginx/nginx.conf" <<EOF
user ${NGX_USER} ${NGX_GROUP};
worker_processes auto;
worker_rlimit_nofile 1024000;
worker_shutdown_timeout 240s;
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

opt_enable "${STRIP}" && {
    log "strip binarys"
    strip ${OUTDIR}/usr/sbin/nginx
    strip ${OUTDIR}/usr/share/nginx/modules/*
}
# final copy other depend files!
opt_enable "${AUTH_JWT}" && {
    pkg-config --exists jansson || { cat ${MYLIB_DEPS}/lib/libjansson.so > ${OUTDIR}/usr/lib/libjansson.so.4; }
    pkg-config --exists libjwt || { cat ${MYLIB_DEPS}/lib/libjwt.so > ${OUTDIR}/usr/lib/libjwt.so.2; }
}
ldd ${OUTDIR}/usr/sbin/nginx 2>/dev/null|| true
ldd ${OUTDIR}/usr/share/nginx/modules/* 2>/dev/null || true
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
INST_SCRIPT=$(mktemp)
UNINST_SCRIPT=$(mktemp)
echo "getent group ${NGX_GROUP} >/dev/null || groupadd --system ${NGX_GROUP} || :" > ${INST_SCRIPT}
echo "getent passwd ${NGX_USER} >/dev/null || useradd -g ${NGX_GROUP} --system -s /sbin/nologin -d /var/empty/nginx ${NGX_USER} 2> /dev/null || :" >> ${INST_SCRIPT}
echo "userdel nginx || :" > ${UNINST_SCRIPT}
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
stage_run fpm && fpm --package ${DIRNAME}/pkg -s dir -t ${PKG} -C ${OUTDIR} --name nginx_johnyin${HTTP3:+_quic} --version $(echo ${NGX_VER}) --iteration ${builder_version} --description "nginx with openssl,other modules" --after-install ${INST_SCRIPT} --after-remove ${UNINST_SCRIPT} .
rm -fr ${INST_SCRIPT} ${UNINST_SCRIPT}
log "ALL PACKAGE OUT: ${DIRNAME}/pkg for ${ID}-${VERSION_ID} ${PKG}"
#rpm -qp --scripts  openssh-server-8.0p1-10.el8.x86_64.rpm
