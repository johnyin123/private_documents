#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

# dpkg --add-architecture arm64 && apt update && apt install libc6:arm64

NGINX_DIR="${1:? MUSL=1/MYARM=1/WIN_MINGW=32/WIN_MINGW=64 $0 <ngx_dir> [lib_dir]}"
MYLIB_DEPS=${2:-${DIRNAME}/mylibs}
NGINX_DIR="$(readlink -f "${NGINX_DIR}")"
MYLIB_DEPS="$(readlink -f "${MYLIB_DEPS}")"
# apt install -y musl-dev musl-tools
OUTDIR=${DIRNAME}/portable_${MYARM:+arm64_}${MUSL:+musl_}${WIN_MINGW:+win${WIN_MINGW}_}ngx/
rm -fr ${OUTDIR} && mkdir -pv ${OUTDIR}/conf ${OUTDIR}/logs ${OUTDIR}/tmp/client_body_temp/ \
    ${OUTDIR}/tmp/proxy_temp/ ${OUTDIR}/tmp/fastcgi_temp/ ${OUTDIR}/tmp/uwsgi_temp/ ${OUTDIR}/tmp/scgi_temp/
SEC_LD_OPTS=$([ -z "${WIN_MINGW:-}" ] && echo "-Wl,-z,relro -Wl,-z,now" || true)
CC_OPTS=${CC_OPTS:-"-DPCRE2_STATIC -DLIBEXSLT_STATIC -DLIBXSLT_STATIC -DLIBXML_STATIC -O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC -I${MYLIB_DEPS}/include -I${MYLIB_DEPS}/include/libxml2 -I${MYLIB_DEPS}/include/quickjs"}
LD_OPTS=${LD_OPTS:-"${SEC_LD_OPTS:-} -fPIC -L${MYLIB_DEPS}/lib -L${MYLIB_DEPS}/lib/quickjs -lexslt -lxslt -lxml2 -lgd -lwebp -lsharpyuv -lpng -ljpeg -lm"}
# for jwt
CC_OPTS="${CC_OPTS} -DNGX_LINKED_LIST_COOKIES=1"
LD_OPTS="${LD_OPTS} -ljwt -Wl,--no-as-needed -ljansson"
# for musl include
CC_OPTS="${CC_OPTS} ${MUSL:+-idirafter /usr/include/ -idirafter /usr/include/$(dpkg-architecture -qDEB_HOST_MULTIARCH)}"
# for mingw libgd static link
CC_OPTS="${CC_OPTS} ${WIN_MINGW:+-DBGDWIN32 -DNONDLL}"
LD_OPTS="${LD_OPTS} ${WIN_MINGW:+-liconv -lbcrypt -lGeoIP -lws2_32}" #win32 bcrypt replace crypt
# for mingw fix ngx_log_debug marco
CC_OPTS="${CC_OPTS} ${WIN_MINGW:+-DNGX_HAVE_GCC_VARIADIC_MACROS}"
# fix ldap liblber and SHUT_RDWR undeclared
CC_OPTS="${CC_OPTS} ${WIN_MINGW:+-DSHUT_RDWR=2}"
LD_OPTS="${LD_OPTS} ${WIN_MINGW:+-lldap -llber}"
# fix rtmp
CC_OPTS="${CC_OPTS} ${WIN_MINGW:+-Wno-sign-compare -Wno-unused-variable}"
# for musl static build and 64 bits file oper
CC_OPTS="${MUSL:+-D_FILE_OFFSET_BITS=64} ${CC_OPTS}"
LD_OPTS="${MUSL:+-static -static-libgcc} ${LD_OPTS}"
# fix sqlite3 error: "_WIN32_WINNT" redefined, and inc/lib
export SQLITE_INC=${MYLIB_DEPS}/include
export SQLITE_LIB=${MYLIB_DEPS}/lib
CC_OPTS="${CC_OPTS} ${WIN_MINGW:+-D_WIN32_WINNT=0x0501 -Wno-macro-redefined -march=i686}"
[ "${WIN_MINGW:-}" == "64" ] && export CC=x86_64-w64-mingw32-gcc
[ "${WIN_MINGW:-}" == "32" ] && export CC=i686-w64-mingw32-gcc
cat <<EOF
------------------------------------
NGX = ${WIN_MINGW:+win${WIN_MINGW}}${MYARM:+(arm64) }${MUSL:+(musl) }${NGINX_DIR}
OUT = ${OUTDIR}
CC  = ${CC_OPTS}
LD  = ${LD_OPTS}
------------------------------------
EOF
read -n 1 -p "Press any key continue build ..." value
# apt install -y musl-dev musl-tools
# ./configure --with-cc="musl-gcc"
cd ${NGINX_DIR} && ln -s auto/configure 2>/dev/null || true
cd ${NGINX_DIR} && { make clean &>/dev/null||true; } && \
    ./configure ${MUSL:+--with-cc="musl-gcc"} \
    ${MYARM:+--with-cc="aarch64-linux-gnu-gcc"} \
    ${WIN_MINGW:+--with-cc="${CC}"
       --crossbuild=win32
       --with-pcre=${DIRNAME}/deps/pcre
       --with-zlib=${DIRNAME}/deps/zlib
       --with-openssl=${DIRNAME}/deps/openssl
       --with-openssl-opt="mingw$([ "${WIN_MINGW}" == "64" ] && echo "64" || true) CFLAGS=-Wno-overflow no-shared no-threads no-dso no-comp no-tests no-legacy no-apps no-docs"} \
    --prefix= \
    --sbin-path=nginx${WIN_MINGW:+.exe} \
    --conf-path=conf/nginx.conf \
    --error-log-path=logs/error.log \
    --http-client-body-temp-path=tmp/client_body_temp/ \
    --http-proxy-temp-path=tmp/proxy_temp/ \
    --http-fastcgi-temp-path=tmp/fastcgi_temp/ \
    --http-uwsgi-temp-path=tmp/uwsgi_temp/ \
    --http-scgi-temp-path=tmp/scgi_temp/ \
    \
    --with-cc-opt="${CC_OPTS}" \
    --with-ld-opt="${LD_OPTS}" \
    --with-pcre-jit \
    --with-compat \
    \
    --with-cpu-opt=generic \
    --with-http_ssl_module \
    \
    --with-http_v2_module \
    $([ -z "${WIN_MINGW:-}" ] && echo "--with-http_v3_module" || true) \
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
    --with-http_flv_module \
    --with-http_mp4_module \
    \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-stream_ssl_preread_module \
    --with-mail$([ -z "${MUSL:-}" ] && echo "=dynamic") \
    --with-mail_ssl_module \
    --with-http_geoip_module$([ -z "${MUSL:-}" ] && echo "=dynamic") \
    --with-stream_geoip_module$([ -z "${MUSL:-}" ] && echo "=dynamic") \
    --with-http_xslt_module$([ -z "${MUSL:-}" ] && echo "=dynamic") \
    --with-http_image_filter_module$([ -z "${MUSL:-}" ] && echo "=dynamic") \
    \
    --add-module=${DIRNAME}/ngx_sqlite \
    --add-module=${DIRNAME}/nginx-http-concat \
    --add-module=${DIRNAME}/nginx-sticky-module-ng \
    $([ -z "${WIN_MINGW:-}" ] && echo "--add-${MYARM:+dynamic-}module=${DIRNAME}/njs/nginx" || true) \
    --add-${MYARM:+dynamic-}${WIN_MINGW:+dynamic-}module=${DIRNAME}/nginx-auth-ldap \
    --add-${MYARM:+dynamic-}${WIN_MINGW:+dynamic-}module=${DIRNAME}/nginx-aws-auth-module \
    --add-${MYARM:+dynamic-}${WIN_MINGW:+dynamic-}module=${DIRNAME}/ngx-http-auth-jwt-module \
    --add-${MYARM:+dynamic-}${WIN_MINGW:+dynamic-}module=${DIRNAME}/ngx_brotli \
    --add-${MYARM:+dynamic-}${WIN_MINGW:+dynamic-}module=${DIRNAME}/nginx-rtmp-module \
    && sed -i "s/NGX_CONFIGURE\s*.*$/NGX_CONFIGURE \"portable version ${WIN_MINGW:+win${WIN_MINGW}}${MYARM:+arm64}${MUSL:+musl}\"/g" objs/ngx_auto_config.h 2>/dev/null \
    && make -j "$(nproc)" -f objs/Makefile binary \
    && make -j "$(nproc)" -f objs/Makefile modules \
    && make -j "$(nproc)" install DESTDIR=${OUTDIR} \
    && rm -f  ${OUTDIR}/conf/*.default || true \
    || { echo "error build portable version"; exit 1; }

${WIN_MINGW:+${CC/gcc/}}${MYARM:+aarch64-linux-gnu-}strip ${OUTDIR}/nginx${WIN_MINGW:+.exe} ${OUTDIR}/modules/* &>/dev/null || true

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
            include fastcgi_params;
            fastcgi_param FN_HANDLER getProfile;
            #try_files $fastcgi_script_name =404;
            fastcgi_pass fcgi_srvs;
        }
    }
}
EOF
(cd ${OUTDIR} &>/dev/null && ./nginx${WIN_MINGW:+.exe} -V)
file ${OUTDIR}/nginx${WIN_MINGW:+.exe} >&2 || true
cat <<EOF
/usr/lib/ld-linux-aarch64.so.1 --list ${OUTDIR}/nginx
ntldd ${OUTDIR}/nginx.exe
EOF
echo "=========================all ok============================"
