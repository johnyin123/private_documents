#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
file_exists() { [ -e "$1" ]; }
ARCH=(amd64 arm64)
type=simplekvm
ver=trixie
nsname=simplekvm

username=simplekvm
USER_HOME=/home/${username}
# VENV=/venv
SSH_PRI=${USER_HOME}/.ssh/id_rsa
SSH_PUB=${USER_HOME}/.ssh/id_rsa.pub
SSH_CFG=${USER_HOME}/.ssh/config
# ${USER_HOME}/.pki/libvirt/cacert.pem
ALL_PRIKEY=${USER_HOME}/.pki/libvirt/clientkey.pem
ALL_PUBKEY=${USER_HOME}/.pki/libvirt/clientcert.pem
# JWT_PUBKEY auto generate from ALL_PRIKEY
JWT_PRIKEY=${ALL_PRIKEY}
JWT_PUBKEY=${USER_HOME}/pubkey.pem
token_dir=/dev/shm/simplekvm/token

SOURCE_DIR=${1:?$(echo "input SOURCE DIR"; exit 1;)}
[ "$(id -u)" -eq 0 ] || { log "need root user run"; exit 1; }
for fn in make_docker_image.sh tpl_overlay.sh; do
    file_exists "${fn}" || { log "${fn} no found"; exit 1; }
done
for fn in ui term novnc.tgz spice.tgz; do
    file_exists "${SOURCE_DIR}/${fn}" || { log "${SOURCE_DIR}/${fn} no found"; exit 1; }
done
for arch in ${ARCH[@]}; do
    file_exists "$(ls nginx-johnyin*${arch}.deb)" || { log "nginx-johnyin ${arch}.deb no found"; }
done

export BUILD_NET=${BUILD_NET:-host}
export REGISTRY=registry.local
export IMAGE=debian:trixie       # # BASE IMAGE
export NAMESPACE=
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    cat <<EODOC > ${type}-${arch}/docker/build.run
set -o nounset -o pipefail -o errexit
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
useradd -u 10001 -m ${username} --home-dir ${USER_HOME}/ --shell /bin/bash || true
echo "need jq,socat,qemu-img(qemu-block-extra),ssh(libvirt open),supervisorctl,openssl"
APT="apt -y ${PROXY:+--option Acquire::http::Proxy=\"${PROXY}\" }--no-install-recommends"
\${APT} update
\${APT} install wget jq openssh-client socat qemu-utils qemu-block-extra openssl 
\${APT} install libjansson4 libjwt2 libldap2 # for nginx
\${APT} install libpython3.13 # for console
\${APT} install python3 supervisor websockify
\${APT} install gunicorn python3-flask python3-libvirt
\${APT} install python3-pycdlib python3-ldap3 python3-jwt python3-etcd3gw python3-requests
# apt -y install libvirt-dev && python3 -m venv venv-full
# pip install libvirt-python==11.3.0 gunicorn Flask pycdlib websockify \
#   ldap3 pyjwt[crypto] requests etcd3gw
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d ! -iname 'zh_CN*' ! -iname 'en*' | xargs -I@ rm -rf @ || true
rm -rf /var/lib/apt/* /var/cache/* /root/.cache /root/.bash_history /usr/share/man/* /usr/share/doc/*
EODOC
target=${type}-${arch}/docker/etc
    mkdir -p ${target}/nginx/http-conf.d/ && cat <<'EODOC' > ${target}/nginx/http-conf.d/cache.conf
proxy_cache_path /dev/shm/cache levels=1:2 keys_zone=SHM_CACHE:10m inactive=60m max_size=16m use_temp_path=off;
map $request_uri $cache_bypass {
    "~(/administrator|/admin|/login)" 1;
    default 0;
}
proxy_no_cache          $cache_bypass;
proxy_cache_bypass      $cache_bypass;
proxy_cache SHM_CACHE;
proxy_cache_key         "$scheme$request_method$host$request_uri";
proxy_cache_lock        on;
proxy_cache_min_uses    1;
proxy_cache_revalidate  on;
proxy_cache_valid       200 301 302 1d;
proxy_cache_valid       404 5m;
proxy_cache_background_update on;
proxy_cache_convert_head off;
proxy_ignore_headers "Cache-Control" "Expires" "Vary" "Set-Cookie" "X-Accel-Expires" "X-Accel-Limit-Rate" "X-Accel-Buffering";
proxy_hide_header    Cache-Control;
proxy_hide_header    Expires;
proxy_hide_header    Pragma;
proxy_hide_header    Set-Cookie;
proxy_hide_header    Vary;
add_header           Pragma "public";
EODOC
    mkdir -p ${target}/nginx/http-enabled/ && echo '{"status":200,"message":"Success"}' > ${target}/nginx/http-enabled/check.json
    mkdir -p ${target}/nginx/http-enabled && cat <<'EODOC'| grep -v '^\s*#.*$' > ${target}/nginx/http-enabled/error_page.inc
error_page 403 = @403;
location @403 { return 403 '{"code":403,"name":"lberr","desc":"Resource Forbidden"}'; }
error_page 404 = @404;
location @404 { return 404 '{"code":404,"name":"lberr","desc":"Resource not found"}'; }
error_page 405 = @405;
location @405 { return 405 '{"code":405,"name":"lberr","desc":"Method not allowed"}'; }
error_page 410 = @410;
location @410 { return 410 '{"code":410,"name":"lberr","desc":"Access expired"}'; }
error_page 502 = @502;
location @502 { return 502 '{"code":502,"name":"lberr","desc":"backend server not alive"}'; }
error_page 504 = @504;
location @504 { return 504 '{"code":504,"name":"lberr","desc":"Gateway Time-out"}'; }
EODOC
    mkdir -p ${target}/nginx/http-enabled && cat <<'EODOC'| grep -v '^\s*#.*$' > ${target}/nginx/http-enabled/favicon.inc
location ~* .(favicon.ico)$ { access_log off; log_not_found off; return 200 '<svg width="104" height="104" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="104" height="104" rx="18" fill="url(#a)"/><path fill-rule="evenodd" clip-rule="evenodd" d="M56 26a4.002 4.002 0 0 1-3 3.874v5.376h15a3 3 0 0 1 3 3v23a3 3 0 0 1-3 3h-8.5v4h3a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-21a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2h3v-4H36a3 3 0 0 1-3-3v-23a3 3 0 0 1 3-3h15v-5.376A4.002 4.002 0 0 1 52 22a4 4 0 0 1 4 4zM21.5 50.75a7.5 7.5 0 0 1 7.5-7.5v15a7.5 7.5 0 0 1-7.5-7.5zm53.5-7.5a7.5 7.5 0 0 1 0 15v-15zM46.5 50a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0zm14.75 3.75a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5z" fill="#fff"/><defs><linearGradient id="a" x1="104" y1="0" x2="0" y2="0" gradientUnits="userSpaceOnUse"><stop stop-color="#34C724"/><stop offset="1" stop-color="#62D256"/></linearGradient></defs></svg>'; }
EODOC
    mkdir -p ${target}/nginx/http-enabled && cat <<'EODOC'| grep -v '^\s*#.*$' > ${target}/nginx/http-enabled/api_auth.conf
upstream real_api_auth {
    server 127.0.0.1:16000;
    keepalive 16;
}
server {
    listen 127.0.0.1:61600;
    server_name _;
    location =/api/login { proxy_cache off; proxy_pass http://real_api_auth; }
    location =/api/refresh { proxy_cache off; proxy_pass http://real_api_auth; }
    location / {
        auth_jwt_enabled on;
        auth_jwt_redirect off;
        auth_jwt_location HEADER=Authorization;
        auth_jwt_algorithm RS256;
        auth_jwt_use_keyfile on;
        auth_jwt_keyfile_path "/etc/nginx/ssl/pubkey.pem";
        alias /etc/nginx/http-enabled/;
        try_files check.json =404;
    }
}
EODOC
    mkdir -p ${target}/nginx/http-enabled && cat <<'EODOC'| grep -v '^\s*#.*$' > ${target}/nginx/http-enabled/simplekvm.conf
upstream api_srv {
    server 127.0.0.1:5009 fail_timeout=0;
    keepalive 16;
}
upstream websockify_srv {
    server 127.0.0.1:6800;
}
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
upstream api_auth {
    server 127.0.0.1:61600;
    keepalive 16;
}
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate     /etc/nginx/ssl/simplekvm.pem;
    ssl_certificate_key /etc/nginx/ssl/simplekvm.key;
    default_type application/json;
    include /etc/nginx/http-enabled/favicon.inc;
    include /etc/nginx/http-enabled/error_page.inc;
    error_page 401 =401 @error401;
    location @error401 { return 401 '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0; url=/login.html?return_url=$scheme://$http_host/ui/tpl.html"/></head><body></body></html>'; }
    location = @api_auth {
        internal;
        proxy_cache off;
        proxy_method 'GET';
        # eat location prefix
        proxy_pass http://api_auth/;
        set $token '';
        if ($cookie_token != '') { set $token 'Bearer $cookie_token'; }
        if ($http_authorization != '') { set $token '$http_authorization'; }
        proxy_set_header Authorization '$token';
        proxy_pass_request_body off;
        proxy_set_header Content-Length '0';
        proxy_set_header X-Origin-URI $request_uri;
    }
    location =/login.html { alias /app/ui/login.html; }
    location =/logout { add_header Set-Cookie 'token='; return 200 '{"status":200,"message":"logout ok"}'; }
    location =/api/login { proxy_cache off; proxy_pass http://api_auth; }
    location =/api/refresh { auth_request @api_auth; proxy_cache off; proxy_pass http://api_auth; }
    location /conf/ {
        location ~* ^/conf/(backup|restore|host|iso|gold)/$ {
            # # no cache!! mgr private access
            limit_except GET POST DELETE { deny all; }
            auth_request @api_auth;
            proxy_cache off;
            expires off;
            proxy_read_timeout 240s;
            client_max_body_size 100m;
            proxy_pass http://api_srv;
        }
        location ~* ^/conf/(|domains/|devices/|ssh_pubkey/)$ {
            auth_request @api_auth;
            limit_except GET { deny all; }
            proxy_cache_valid 200   5m;
            proxy_pass http://api_srv;
        }
        location ~* ^/conf/add_authorized_keys/(?<others>.*)$ {
            auth_request @api_auth;
            limit_except POST { deny all; }
            proxy_pass http://api_srv;
        }
        absolute_redirect off; return 301 /ui/tpl.html;
    }
    location /tpl/ {
        # # proxy cache default is on, so modify host|device|gold, should clear ngx cache
        auth_request @api_auth;
        # host/device/gold can cached by proxy_cache default
        proxy_cache_valid 200   5m;
        location ~* ^/tpl/(?<apicmd>(host|device|gold|iso))/(?<others>.*)$ {
            if ($request_method !~ ^(GET)$) { return 405; }
            # # rewrite .....
            proxy_pass http://api_srv/tpl/$apicmd/$others$is_args$args;
        }
        absolute_redirect off; return 301 /ui/tpl.html;
    }
    location = @prestart {
        internal;
        proxy_cache off;
        proxy_method 'GET';
        proxy_pass http://api_srv$auth_request_uri;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }
    location /vm/ {
        auth_request @api_auth;
        # # no cache!! mgr private access
        proxy_cache off;
        expires off;
        proxy_read_timeout 240s;
        location ~* ^/vm/(?<apicmd>(snapshot))/(?<others>.*)$ {
            if ($request_method !~ ^(GET|POST)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/$apicmd/$others$is_args$args;
        }
        location ~* ^/vm/(?<apicmd>(ipaddr|blksize|netstat|desc|setmem|setcpu|list|start|reset|stop|delete|display|xml|ctrl_url|revert_snapshot|delete_snapshot))/(?<others>.*)$ {
            if ($request_method !~ ^(GET)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/$apicmd/$others$is_args$args;
        }
        location ~* ^/vm/(?<apicmd>(create|attach_device|detach_device|cdrom|metadata))/(?<others>.*)$ {
            if ($request_method !~ ^(POST)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/$apicmd/$others$is_args$args;
        }
        location ~* ^/vm/websockify/(?<kvmhost>.*)/(?<uuid>.*)$ {
            set $auth_request_uri "/vm/websockify/$kvmhost/$uuid$is_args$args";
            auth_request @prestart;
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_pass http://websockify_srv/websockify/$is_args$args;
        }
        absolute_redirect off; return 301 /ui/tpl.html;
    }
    # # admin ui # #
    location = / { absolute_redirect off; return 301 /ui/tpl.html; }
    location = /ui/tpl.html {
        auth_request @api_auth;
        alias /app/ui/tpl.html;
    }
    # # guest ui
    location = /guest.html { return 301 https://$host:1443/ui/userui.html$is_args$args; }
    # # static resource # #
    # # ui/term/spice/novnc use api_srv serve, add rewrite
    # rewrite ^ /public$uri break;proxy_pass http://api_srv;
    location /ui    { alias /app/ui/; }
    location /term  { alias /app/term/; }
    location /spice { alias /app/spice/; }
    location /novnc { alias /app/novnc/; }
}
server {
    listen 1443 ssl;
    server_name _;
    ssl_certificate     /etc/nginx/ssl/simplekvm.pem;
    ssl_certificate_key /etc/nginx/ssl/simplekvm.key;
    default_type application/json;
    include /etc/nginx/http-enabled/favicon.inc;
    include /etc/nginx/http-enabled/error_page.inc;
    # # tanent api
    location = @prestart_user {
        internal;
        proxy_cache off;
        proxy_method 'GET';
        proxy_pass http://api_srv$user_auth_request_uri;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }
    location /user/ {
        location ~* ^/user/vm/websockify/(?<kvmhost>.*)/(?<uuid>.*)$ {
            proxy_cache off;
            expires off;
            # # first secure_link check, then auth_request
            set $user_auth_request_uri "/vm/websockify/$kvmhost/$uuid$is_args$args";
            auth_request @prestart_user;
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            rewrite ^/user(.*)$ $1 break;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_pass http://websockify_srv;
        }
        location ~* ^/user/vm/(?<apicmd>(snapshot))/(?<kvmhost>.*)/(?<uuid>.*)$ {
            # # no cache!! guest user api, guest private access
            proxy_cache off;
            expires off;
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            if ($request_method !~ ^(GET|POST)$ ) { return 405; }
            rewrite ^/user(.*)$ $1 break;
            proxy_pass http://api_srv;
        }
        location ~* ^/user/vm/(?<apicmd>(list|start|reset|stop|display|revert_snapshot|delete_snapshot))/(?<kvmhost>.*)/(?<uuid>.*)$ {
            # # no cache!! guest user api, guest private access
            proxy_cache off;
            expires off;
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            if ($request_method !~ ^(GET)$ ) { return 405; }
            rewrite ^/user(.*)$ $1 break;
            proxy_pass http://api_srv;
        }
        location ~* ^/user/vm/(?<apicmd>(cdrom))/(?<kvmhost>.*)/(?<uuid>.*)$ {
            # # no cache!! guest user api, guest private access
            proxy_cache off;
            expires off;
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            if ($request_method !~ ^(POST)$) { return 405; }
            rewrite ^/user(.*)$ $1 break;
            proxy_pass http://api_srv;
        }
        location ~* ^/user/vm/(?<apicmd>(getiso))/(?<kvmhost>.*)/(?<uuid>.*)$ {
            # # /tpl/iso need cache
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            if ($request_method !~ ^(GET)$) { return 405; }
            set $urieat '';
            # # just for eating uri -> /tpl/iso/,no args, can cache
            proxy_pass http://api_srv/tpl/iso/$urieat;
            # rewrite ^.*$ /tpl/iso/ break;
            # # /tpl/iso/?k=XtaHHDjE_nULHFdM2Dsupw&e=1745423940. with args, can not cache
            # proxy_pass http://api_srv;
        }
        absolute_redirect off; return 301 /guest.html;
    }
    # # default page is guest ui
    location / { return 301 https://$host/ui/userui.html; }
    # # tanent user UI manager # #
    location = /guest.html { absolute_redirect off; return 301 /ui/userui.html$is_args$args; }
    # # static resource # #
    # # ui/term/spice/novnc use api_srv serve, add rewrite
    # rewrite ^ /public$uri break;proxy_pass http://api_srv;
    location /ui    { alias /app/ui/; }
    location /term  { alias /app/term/; }
    location /spice { alias /app/spice/; }
    location /novnc { alias /app/novnc/; }
}
EODOC
    mkdir -p ${target}/nginx/http-enabled && cat <<EODOC| grep -v '^\s*#.*$' > ${target}/nginx/http-enabled/meta_golds.conf
server {
    listen 80;
    server_name _;
    location ~* (\/cidata\.iso|\/meta-data|\/user-data)$ { access_log off; log_not_found on; set \$limit 0; if_modified_since before; root /dev/shm/simplekvm/work/cidata; }
    include /etc/nginx/http-enabled/gold_iso.loc;
}
EODOC
    mkdir -p ${target}/nginx/http-enabled && cat <<EODOC| grep -v '^\s*#.*$' > ${target}/nginx/http-enabled/gold_iso.loc
location ~*\.(iso)$ {
    proxy_cache off;
    proxy_set_header Host real_gold_srv;
    proxy_pass http://real_gold_srv;
}
location ~*\.(qcow2)$ {
    access_log off; log_not_found on; set \$limit 0; if_modified_since before; root ${USER_HOME}/golds;
    try_files \$request_uri @real_res;
}
location @real_res {
    proxy_cache off;
    set \$reqfile \$uri;
    mirror /mirror_store;
    mirror_request_body off;
    proxy_set_header Accept-Encoding "";
    proxy_set_header Host real_gold_srv;
    proxy_pass http://real_gold_srv;
}
location = /mirror_store {
    internal;
    proxy_cache off;
    # proxy_method GET; # Force GET so HEAD trigger a full file download
    proxy_pass http://real_gold_srv\$request_uri;
    proxy_set_header Accept-Encoding "";
    proxy_set_header Host real_gold_srv
    proxy_set_header Range "";
    proxy_set_header If-Range "";
    proxy_store ${USER_HOME}/golds\$reqfile;
    proxy_store_access user:rw group:rw all:r;
    proxy_ignore_client_abort off;
}
location / {
    proxy_cache off;
    proxy_set_header Host real_gold_srv;
    proxy_pass http://real_gold_srv;
}
EODOC
    mkdir -p ${target} && cat <<EODOC |  grep -v '^\s*#.*$' > ${target}/supervisord.conf
[supervisord]
nodaemon=true
user=root
environment=PATH="${VENV:+${VENV}/bin:}%(ENV_PATH)s"
logfile=/dev/stdout
logfile_maxbytes=0
pidfile=/var/run/supervisord.pid

[unix_http_server]
file=/var/run/supervisor.sock   ; path to your socket file
chmod=0700
chown=${username}:${username}
[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
[supervisorctl]
serverurl=unix:///var/run/supervisor.sock ; must match the [unix_http_server] file path

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
startretries=10
startsecs=1
user=root
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:websockify]
command=websockify --token-plugin TokenFile --token-source ${token_dir} 127.0.0.1:6800
autostart=true
autorestart=true
startretries=10
startsecs=1
user=${username}
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:api_auth]
umask=0022
environment=JWT_PUBKEY=${JWT_PUBKEY},JWT_PRIKEY=${JWT_PRIKEY}
command=gunicorn --chdir /auth -b 127.0.0.1:16000 --max-requests 50000 --preload --workers=1 --threads=2 --access-logformat 'JWT %%(r)s %%(s)s %%(M)sms len=%%(B)s' --access-logfile='-' 'api_auth:create_app()'
autostart=true
autorestart=true
startretries=5
user=${username}
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:simplekvm]
umask=0022
environment=HOME="${USER_HOME}",TOKEN_DIR="${token_dir}"
command=gunicorn --chdir /app -b 127.0.0.1:5009 --max-requests 50000 --preload --workers=1 --threads=2 --access-logformat 'API %%(r)s %%(s)s %%(M)sms len=%%(B)s' --access-logfile='-' 'main:create_app()'
autostart=true
autorestart=true
startretries=10
startsecs=1
user=${username}
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC
    mkdir -p ${type}-${arch}/docker/ && cat <<EODOC >${type}-${arch}/docker/entrypoint.sh
#!/bin/bash
file_exists() { [ -e "\$1" ]; }
mkdir -p $(dirname "${ALL_PRIKEY}") ${USER_HOME}/golds
file_exists "${ALL_PRIKEY}" || openssl req -quiet -x509 -newkey rsa:2048 -keyout ${ALL_PRIKEY} -out ${ALL_PUBKEY} -sha256 -days 3650 -nodes -subj "/C=CN/L=LN/O=mycompany/CN=SimpleKVM"
file_exists "${JWT_PUBKEY}" || openssl rsa -in ${ALL_PRIKEY} -pubout -out ${JWT_PUBKEY} || true
file_exists "${SSH_PRI}" || {
    mkdir --mode=700 -p "${USER_HOME}/.ssh"
    ssh-keygen -q -b 4096 -t rsa -C simplekvm -N '' -f ${SSH_PRI}
}
file_exists "${SSH_CFG}" || cat <<EO_CFG > "${SSH_CFG}"
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
ControlMaster auto
ControlPath  ~/.ssh/%r@%h:%p
ControlPersist 600
Ciphers aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha1
EO_CFG
chown -R ${username}:${username} ${USER_HOME} -R || true
chmod 600 ${SSH_PRI} || true
chmod 644 ${SSH_PUB} || true
chmod 644 ${SSH_CFG} || true
[ -z "\${CTRL_KEY:-}" ] || {
    sed -i "s|P@ssw@rd4Display|\${CTRL_KEY}|g" /etc/nginx/http-enabled/simplekvm.conf || true
}
[ -z "\${ETCD_PREFIX:-}" ] && {
    sed -i "s|/dev/shm/simplekvm/work/cidata|\${DATA_DIR:-${USER_HOME}/work}/cidata|g" /etc/nginx/http-enabled/meta_golds.conf || true
}
[ -z "\${GOLD_SRV:-}" ] && {
    echo "location / { root ${USER_HOME}/golds; }" > /etc/nginx/http-enabled/gold_iso.loc
} || {
    # cache golds
    sed -i \\
        -e "s|proxy_set_header\s\s*Host.*$|proxy_set_header Host \${GOLD_SRV};|g" \\
        -e "s|proxy_pass\s\s*http://[^;\$]*|proxy_pass http://\${GOLD_SRV}|g" \\
        /etc/nginx/http-enabled/gold_iso.loc || true
    # export GOLD_CACHE=1
}
# 443 is simplekvm admin server, :1443 is tanent server, :80 is META_SRV and GOLD_SRV
env || true
exec "\$@"
EODOC
    chmod 755 ${type}-${arch}/docker/entrypoint.sh
    cat <<EODOC >> ${type}-${arch}/Dockerfile
EXPOSE 80 443 1443
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisord.conf"]
EODOC
    ################################################
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --name ${type}-${arch}.baseimg --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m || true
    rm -f ${type}-${arch}.baseimg.tpl || true
    docker export ${type}-${arch}.baseimg | mksquashfs - ${type}-${arch}.baseimg.tpl -tar # -quiet
    docker rm -v ${type}-${arch}.baseimg
    log "Pre chroot, copy files in ${type}-${arch}/docker/"
    file_exists "$(ls nginx-johnyin*${arch}.deb)" && dpkg -x "$(ls nginx-johnyin*${arch}.deb)" ${type}-${arch}/docker
    sed -i "s/^\s*#\s*//g" ${target}/nginx/modules.d/jwt.conf
    sed -i "s/^user .*;/user ${username} ${username};/g"  ${target}/nginx/nginx.conf
    sed -i "s/worker_processes .*;/worker_processes 2;/g" ${target}/nginx/nginx.conf
    sed -i "/worker_priority/d"                           ${target}/nginx/nginx.conf
    sed -i "/proxy_pass_header\s*Server\s*;/d"            ${target}/nginx/http-conf.d/proxy.conf
    rm -f ${target}/nginx/ssl/simplekvm.pem && ln -s ${ALL_PUBKEY} ${target}/nginx/ssl/simplekvm.pem
    rm -f ${target}/nginx/ssl/simplekvm.key && ln -s ${ALL_PRIKEY} ${target}/nginx/ssl/simplekvm.key
    rm -f ${target}/nginx/ssl/pubkey.pem    && ln -s ${JWT_PUBKEY} ${target}/nginx/ssl/pubkey.pem
    mkdir -p ${type}-${arch}/docker/app && {
        tar -C ${type}-${arch}/docker/app --exclude=include -xf ${SOURCE_DIR}/novnc.tgz
        tar -C ${type}-${arch}/docker/app -xf ${SOURCE_DIR}/spice.tgz --transform 's/^spice.*master/spice/'
        tar --exclude=test -C ${SOURCE_DIR} -c ui term | tar -C ${type}-${arch}/docker/app -x
        ######### gen init env tgz file
        INIT_TPL=(meta/meta-data.tpl meta/user-data.tpl devices/disk.file.tpl devices/disk.file.action devices/net.br-ext.tpl devices/cdrom.null.tpl domains/domain.tpl vars.json)
        INIT_DBS=(golds.json iso.json)
        tmp_dir=$(mktemp -d "/tmp/simplekvm-init-$(date +'%Y%m%d%H%M%S')-XXXXXXXXXX")
        cat <<'EOF' > ${tmp_dir}/golds.json
[{"name":"","arch":"x86_64","uri":"","size":1,"desc":"数据盘"},{"name":"","arch":"aarch64","uri":"","size":1,"desc":"数据盘"}]
EOF
        cat <<'EOF' > ${tmp_dir}/iso.json
[{"name":"","uri":"","desc":"MetaData ISO"}]
EOF
        for fn in ${INIT_TPL[@]}; do
            target=${tmp_dir}/${fn}
            mkdir -p $(dirname "${target}") && cat "${SOURCE_DIR}/${fn}" > "${target}"
        done
        tar -C ${tmp_dir} -c ${INIT_TPL[@]} ${INIT_DBS[@]} | gzip > ${type}-${arch}/docker/app/init_env.tgz
        rm -rf ${tmp_dir}
    }
    mkdir -p ${type}-${arch}/docker/auth
    log "Pre chroot exit"
    ./tpl_overlay.sh -t ${type}-${arch}.baseimg.tpl -r ${type}-${arch}.rootfs --upper ${type}-${arch}/docker
    log "chroot ${type}-${arch}.rootfs,(copy app/auth) exit continue build"
    chroot ${type}-${arch}.rootfs /usr/bin/env -i SHELL=/bin/bash PS1="\u@DOCKER-${arch}:\w$" TERM=${TERM:-} COLORTERM=${COLORTERM:-} /bin/bash --noprofile --norc -o vi || true
    log "exit ${type}-${arch}.rootfs"
    ./tpl_overlay.sh -r ${type}-${arch}.rootfs -u
    log "Post chroot, delete nouse file in ${type}-${arch}/docker/"
    for fn in tmp root build.run $(ls nginx-johnyin*${arch}.deb); do
        rm -fr ${type}-${arch}/docker/${fn}
    done
    rm -vfr ${type}-${arch}.baseimg.tpl ${type}-${arch}.rootfs
done
log '=================================================='
for arch in ${ARCH[@]}; do
    log docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    log ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
    log docker push ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
done
log ./make_docker_image.sh -c combine --tag ${REGISTRY}/${nsname}/${type}:${ver}

trap "exit -1" SIGINT SIGTERM
read -n 1 -t 10 -p "Continue build(Y/n)? 10s timeout, default n" value || true
if [ "${value}" = "y" ]; then
    for arch in ${ARCH[@]}; do
        docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
        ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
        docker push ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
    done
    ./make_docker_image.sh -c combine --tag ${REGISTRY}/${nsname}/${type}:${ver}
fi
cat <<'EOF'
###################################################
# test run
###################################################
META_SRV=vmm.registry.local
GOLD_SRV=vmm.registry.local  # noset use docker local ip:80 as gold/iso srv
gold_srv_ipaddr=192.168.167.1
LDAP_SRV_URL=ldap://ldap:10389 # noset use test env admin/simplekvm
ETCD_PREFIX=/simple-kvm/work  # noset use local store, not cluster mode

# --env LEVELS='{"main":"INFO"}' \
docker create --name simplekvm --restart always \
 --network br-int --ip 192.168.169.123 \
 --env JWT_ALLOWS='["admin", "simplekvm"]' \
 --env LDAP_SRV_URL=${LDAP_SRV_URL} \
 --env META_SRV=${META_SRV} \
 --env GOLD_SRV=${GOLD_SRV} --add-host ${GOLD_SRV}:${gold_srv_ipaddr} \
 --env ETCD_PREFIX=${ETCD_PREFIX} --env ETCD_SRV=etcd --env ETCD_PORT=2379 \

 # -v ${TARGET_DIR}:/home/simplekvm
EOF

