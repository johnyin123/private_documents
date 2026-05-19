#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

NGINX_DIR="${1:? MUSL=1 $0 <ngx_dir> [lib_dir]}"
MYLIB_DEPS=${2:-${DIRNAME}/mylibs}
NGINX_DIR="$(readlink -f "${NGINX_DIR}")"
MYLIB_DEPS="$(readlink -f "${MYLIB_DEPS}")"
# apt install -y musl-dev musl-tools
MUSL_CFLAGS=${MUSL:+-D_FILE_OFFSET_BITS=64}

OUTDIR=${DIRNAME}/portable_ngx/
rm -fr ${OUTDIR} && mkdir -pv ${OUTDIR}/conf ${OUTDIR}/logs ${OUTDIR}/tmp/client_body_temp/ \
    ${OUTDIR}/tmp/proxy_temp/ ${OUTDIR}/tmp/fastcgi_temp/ ${OUTDIR}/tmp/uwsgi_temp/ ${OUTDIR}/tmp/scgi_temp/
CC_OPTS="-static -static-libgcc -O2 ${MUSL_CFLAGS} -fstack-protector-strong -Wformat -Werror=format-security -fPIC -I${MYLIB_DEPS}/include -I${MYLIB_DEPS}/include/libxml2"
LD_OPTS="-static -L${MYLIB_DEPS}/lib -lxml2"
# for jwt
CC_OPTS="${CC_OPTS} -DNGX_LINKED_LIST_COOKIES=1"
LD_OPTS="${LD_OPTS} -ljwt -Wl,--no-as-needed -ljansson"
# for musl include
CC_OPTS="${CC_OPTS} ${MUSL:+-idirafter /usr/include/ -idirafter /usr/include/$(dpkg-architecture -qDEB_HOST_MULTIARCH)}"

#
# apt install -y musl-dev musl-tools
# ./configure --with-cc="musl-gcc"
cd ${NGINX_DIR} && ln -s auto/configure 2>/dev/null || true
cd ${NGINX_DIR} && { make clean &>/dev/null||true; } && \
    ./configure ${MUSL:+--with-cc="musl-gcc"} \
    --with-cc-opt="${CC_OPTS}" \
    --with-ld-opt="${LD_OPTS}" \
    --prefix=. \
    --sbin-path=nginx \
    --conf-path=conf/nginx.conf \
    --error-log-path=logs/error.log \
    --http-client-body-temp-path=tmp/client_body_temp/ \
    --http-proxy-temp-path=tmp/proxy_temp/ \
    --http-fastcgi-temp-path=tmp/fastcgi_temp/ \
    --http-uwsgi-temp-path=tmp/uwsgi_temp/ \
    --http-scgi-temp-path=tmp/scgi_temp/ \
    \
    --with-pcre \
    --with-pcre-jit \
    --with-compat \
    --with-cpu-opt=generic \
    --with-http_ssl_module \
    \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_xslt_module \
    --with-http_geoip_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_auth_request_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_stub_status_module \
    \
    --add-module=${DIRNAME}/njs/nginx \
    --add-module=${DIRNAME}/nginx-http-concat \
    --add-module=${DIRNAME}/nginx-rtmp-module \
    --add-module=${DIRNAME}/nginx-sticky-module-ng \
    --add-module=${DIRNAME}/nginx-auth-ldap \
    --add-module=${DIRNAME}/nginx-aws-auth-module \
    --add-module=${DIRNAME}/ngx-http-auth-jwt-module \
    && sed -i "s/NGX_CONFIGURE\s*.*$/NGX_CONFIGURE \"portable version for fastcgi\"/g" objs/ngx_auto_config.h 2>/dev/null \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install DESTDIR=${OUTDIR} \
    && strip ${OUTDIR}/nginx

   # --add-module=${DIRNAME}/ngx_brotli \
   # --add-module=${DIRNAME}/ngx_sqlite \

cat <<'EOF' > ${OUTDIR}/conf/nginx.conf
worker_processes  1;
# Relative path for PID file
pid logs/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;

    # Relative paths for logs
    access_log  logs/access.log;
    error_log   logs/error.log;
    upstream fcgi_srvs {
            server 127.0.0.1:9999;
            server unix:/tmp/fastcgi.socket;
            keepalive 16;
    }
    limit_conn_zone $server_name zone=connperserver:10m;
    server {
        listen 127.0.0.1:29999;
        server_name _;
        error_page 403 = @403;
        location @403 { return 403 '{"code":403,"name":"lberr","desc":"Resource Forbidden"}'; }
        error_page 405 = @405;
        location @405 { return 405 '{"code":405,"name":"lberr","desc":"Method not allowed"}'; }
        location / {
            limit_conn connperserver 1;
            limit_conn_status 403;
            allow 127.0.0.1;
            deny all;
            fastcgi_keep_conn on;
            if ($request_method !~ ^(GET|POST)$) { return 405; }
            include /etc/nginx/fastcgi_params;
            fastcgi_param FN_HANDLER getProfile;
            #try_files $fastcgi_script_name =404;
            fastcgi_pass fcgi_srvs;
        }
    }
}
EOF
(cd ${OUTDIR} && ./nginx -t)
echo "=========================all ok============================"
