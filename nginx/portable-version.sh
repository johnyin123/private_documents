#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
MYCROSS=${MYCROSS:-}  # x86_64-w64-mingw32 / i686-w64-mingw32 / aarch64-linux-gnu
WIN_TGT=linux-x86_64
[ "${MYCROSS:-}" == "i686-w64-mingw32" ] && { WIN_TGT=mingw; MYCURL_LIB="-lws2_32 -lgdi32 -lcrypt32"; }
[ "${MYCROSS:-}" == "x86_64-w64-mingw32" ] && { WIN_TGT=mingw64; MYCURL_LIB="-lws2_32 -lgdi32 -lcrypt32"; }
[ "${MYCROSS:-}" == "aarch64-linux-gnu" ] && WIN_TGT=linux-aarch64

OUTDIR=${DIRNAME}/portable_ngx/
mkdir -pv  \
${OUTDIR}/conf \
${OUTDIR}/logs \
${OUTDIR}/tmp/client_body_temp/ \
${OUTDIR}/tmp/proxy_temp/ \
${OUTDIR}/tmp/fastcgi_temp/ \
${OUTDIR}/tmp/uwsgi_temp/ \
${OUTDIR}/tmp/scgi_temp/
CC_OPTS=${CC_OPTS:-"-static -static-libgcc -O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC"}
LD_OPTS=${LD_OPTS:-"-static -Wl,-z,relro -Wl,-z,now -fPIC"}
MYLIB_DEPS=${DIRNAME}/mylibs
[ -d "${MYLIB_DEPS}" ] || {
    (cd openssl && { make distclean||true; } && ./Configure ${MYCROSS:+${WIN_TGT} --cross-compile-prefix=${MYCROSS}-} \
        LIBDIR=lib --prefix=${MYLIB_DEPS} no-zstd no-zlib \
        no-shared no-threads no-tests no-legacy no-apps no-docs \
        && perl configdata.pm --dump \
        && make LIBDIR=lib -j "$(nproc)" build_libs \
        && make LIBDIR=lib -j "$(nproc)" install_sw) || { echo  'error~~openssl'; exit 1; }

    (cd zlib && { make distclean||true; } && ./configure --prefix=${MYLIB_DEPS} --static \
        && make -j "$(nproc)" \
        && make -j "$(nproc)" install) || { echo  'error~~zlib'; exit 1; }

    (cd pcre2 && { make distclean||true; } && ./configure --prefix=${MYLIB_DEPS} --enable-jit --enable-static=yes --enable-shared=no \
        && make -j "$(nproc)" \
        && make -j "$(nproc)" install) || { echo  'error~~pcre2'; exit 1; }
}
./configure \
    --with-cc-opt="${CC_OPTS} -I${MYLIB_DEPS}/include" \
    --with-ld-opt="${LD_OPTS} -L${MYLIB_DEPS}/lib" \
    --prefix=. \
    --sbin-path=. \
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
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module \
    --without-stream_limit_conn_module \
    --without-stream_access_module \
    --without-stream_geo_module \
    --without-stream_map_module \
    --without-stream_split_clients_module \
    --without-stream_return_module \
    --without-stream_pass_module \
    --without-stream_set_module \
    --without-stream_upstream_hash_module \
    --without-stream_upstream_least_conn_module \
    --without-stream_upstream_random_module \
    --without-stream_upstream_zone_module \
    \
    --without-quic_bpf_module \
    --without-http_charset_module \
    --without-http_gzip_module \
    --without-http_ssi_module \
    --without-http_userid_module \
    --without-http_auth_basic_module \
    --without-http_mirror_module \
    --without-http_autoindex_module \
    --without-http_geo_module \
    --without-http_map_module \
    --without-http_split_clients_module \
    --without-http_referer_module \
    --without-http_proxy_module \
    --without-http_uwsgi_module \
    --without-http_scgi_module \
    --without-http_grpc_module \
    --without-http_memcached_module \
    --without-http_limit_req_module \
    --without-http_empty_gif_module \
    --without-http_browser_module \
    --without-http_upstream_hash_module \
    --without-http_upstream_ip_hash_module \
    --without-http_upstream_least_conn_module \
    --without-http_upstream_zone_module \
    --without-http-cache \
    && sed -i "s/NGX_CONFIGURE\s*.*$/NGX_CONFIGURE \"portable version for fastcgi\"/g" objs/ngx_auto_config.h 2>/dev/null \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install DESTDIR=${OUTDIR} \

# cd NGX_DIR && ./nginx -p . -c conf/nginx.conf

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

