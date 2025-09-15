#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
file_exists() { [ -e "$1" ]; }
ARCH=(amd64 arm64)

type=simplekvm
ver=trixie
username=simplekvm
VENV=/home/${username}/venv

SOURCE_DIR=${1:?$(echo "input SOURCE DIR"; exit 1;)}
for fn in make_docker_image.sh tpl_overlay.sh; do
    file_exists "${fn}" || { log "${fn} no found"; exit 1; }
done
for fn in ui term novnc.tgz spice.tgz; do
    file_exists "${SOURCE_DIR}/${fn}" || { log "${SOURCE_DIR}/${fn} no found"; exit 1; }
done
for arch in ${ARCH[@]}; do
    file_exists nginx-johnyin_${arch}.deb || { log "nginx-johnyin_${arch}.deb no found"; exit 1; }
done

export BUILD_NET=${BUILD_NET:-host}
export REGISTRY=registry.local
export IMAGE=debian:trixie       # # BASE IMAGE
export NAMESPACE=
token_dir=/dev/shm/simplekvm/token
out_dir=/dev/shm/simplekvm/work
etcd_prefix=/simple-kvm/work
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    cat <<EODOC > ${type}-${arch}/docker/build.run
set -o nounset -o pipefail -o errexit
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
useradd -u 10001 -m ${username} --home-dir /home/${username}/ --shell /bin/bash
dpkg -i nginx-johnyin_${arch}.deb || true
sed -i "s/^user .*;/user ${username} ${username};/g"  /etc/nginx/nginx.conf
sed -i "s/worker_processes .*;/worker_processes 1;/g" /etc/nginx/nginx.conf
sed -i "/worker_priority/d"                           /etc/nginx/nginx.conf
echo "need jq,socat,qemu-img(qemu-block-extra),ssh(libvirt open)"
APT="apt -y ${PROXY:+--option Acquire::http::Proxy=\"${PROXY}\" }--no-install-recommends"
\${APT} update
\${APT} install jq openssh-client socat qemu-utils qemu-block-extra supervisor python3 python3-venv
\${APT} install libbrotli1 libgeoip1 libxml2 libxslt1.1 libjansson4 libsqlite3-0 libldap2 libjwt2
# libjwt0 libldap-2.5-0
\${APT} install python3-libvirt python3-protobuf python3-markupsafe python3-certifi python3-charset-normalizer python3-requests python3-urllib3

python3 -m venv --system-site-packages /home/${username}/venv
. /home/${username}/venv/bin/activate
cat <<EO_PIP | grep -v '^\s*#.*$' > /home/${username}/requirements.txt
gunicorn
Flask
pycdlib
websockify
etcd3
# etcd3 use grpcio someversion bug when Docker, so use system python3-protobuf
EO_PIP
pip install ${PROXY:+--proxy ${PROXY} }-r /home/${username}/requirements.txt
rm -f /home/${username}/requirements.txt
chown -R 10001:10001 /home/${username}/venv
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d ! -iname 'zh_CN*' ! -iname 'en*' | xargs -I@ rm -rf @ || true
rm -rf /var/lib/apt/* /var/cache/* /root/.cache /root/.bash_history /usr/share/man/* /usr/share/doc/*
EODOC
    mkdir -p ${type}-${arch}/docker/etc/nginx/http-conf.d/ && cat <<'EODOC' > ${type}-${arch}/docker/etc/nginx/http-conf.d/cache.conf
proxy_cache_path /dev/shm/cache levels=1:2 keys_zone=SHM_CACHE:10m inactive=1h max_size=16m use_temp_path=off;
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
    mkdir -p ${type}-${arch}/docker/etc/nginx/http-enabled && cat <<'EODOC'| grep -v '^\s*#.*$' > ${type}-${arch}/docker/etc/nginx/http-enabled/simplekvm.conf
upstream api_srv {
    server 127.0.0.1:5009 fail_timeout=0;
    keepalive 64;
}
upstream websockify_srv {
    server 127.0.0.1:6800;
}
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate     /etc/nginx/ssl/simplekvm.pem;
    ssl_certificate_key /etc/nginx/ssl/simplekvm.key;
    default_type application/json;
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
    #include /etc/nginx/http-enabled/jwt_sso_auth.inc;
    location /tpl/ {
        # # proxy cache default is on, so modify host|device|gold, should clear ngx cache
        #auth_request @sso-auth;
        # host/device/gold can cached by proxy_cache default
        location ~* ^/tpl/(?<apicmd>(host|device|gold|iso))/(?<others>.*)$ {
            if ($request_method !~ ^(GET)$) { return 405; }
            # # rewrite .....
            proxy_pass http://api_srv/tpl/$apicmd/$others$is_args$args;
        }
        return 404;
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
        #auth_request @sso-auth;
        # # no cache!! mgr private access
        proxy_cache off;
        expires off;
        proxy_read_timeout 240s;
        location ~* ^/vm/(?<apicmd>(ipaddr|blksize|netstat|desc|setmem|setcpu|list|start|reset|stop|delete|display|xml|ui))/(?<others>.*)$ {
            if ($request_method !~ ^(GET)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/$apicmd/$others$is_args$args;
        }
        location ~* ^/vm/(?<apicmd>(create|attach_device|detach_device|cdrom))/(?<others>.*)$ {
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
        return 404;
    }
    # # admin ui # #
    location = / { absolute_redirect off; return 301 /ui/tpl.html; }
    location = /ui/tpl.html {
        #auth_request @sso-auth;
        alias /app/ui/tpl.html;
    }
    # # static resource # #
    # # ui/term/spice/novnc use api_srv serve, add rewrite
    # rewrite ^ /public$uri break;proxy_pass http://api_srv;
    location /ui { alias    /app/ui/; }
    location /term { alias  /app/term/; }
    location /spice { alias /app/spice/; }
    location /novnc { alias /app/novnc/; }
}
server {
    listen 80;
    server_name _;
    location / { return 301 https://$host$request_uri; }
    location ~* (\.iso|\/meta-data|\/user-data)$ { set $limit 0; root /dev/shm/simplekvm/work/cidata; }
}
server {
    listen 1443 ssl;
    server_name _;
    ssl_certificate     /etc/nginx/ssl/simplekvm.pem;
    ssl_certificate_key /etc/nginx/ssl/simplekvm.key;
    default_type application/json;
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
        location ~* ^/user/vm/(?<apicmd>(list|start|reset|stop|display))/(?<kvmhost>.*)/(?<uuid>.*)$ {
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
        return 403;
    }
    # # default page is guest ui
    location / { return 301 https://$host/ui/userui.html; }
    # # tanent user UI manager # #
    location = /guest.html { absolute_redirect off; return 301 /ui/userui.html$is_args$args; }
    # # static resource # #
    # # ui/term/spice/novnc use api_srv serve, add rewrite
    # rewrite ^ /public$uri break;proxy_pass http://api_srv;
    location /ui { alias    /app/ui/; }
    location /term { alias  /app/term/; }
    location /spice { alias /app/spice/; }
    location /novnc { alias /app/novnc/; }
}
EODOC
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
environment=PATH="${VENV:+${VENV}/bin:}%(ENV_PATH)s"
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
startretries=5
user=root
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:websockify]
command=websockify --token-plugin TokenFile --token-source ${token_dir} 127.0.0.1:6800
autostart=true
autorestart=true
startretries=5
user=${username}
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:gunicorn]
umask=0022
environment=ETCD_PREFIX="${etcd_prefix}",DATA_DIR="${out_dir}",TOKEN_DIR="${token_dir}",PYTHONDONTWRITEBYTECODE=1
directory=/app/
command=gunicorn -b 127.0.0.1:5009 --max-requests 50000 --preload --workers=1 --threads=2 --access-logformat 'API %%(r)s %%(s)s %%(M)sms len=%%(B)s' --access-logfile='-' 'main:app'
autostart=true
autorestart=true
startretries=5
user=${username}
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
EXPOSE 80 443 1443
ENTRYPOINT ["/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisord.conf"]
EODOC
    ################################################
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --name ${type}-${arch}.baseimg --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m || true
    rm -f ${type}-${arch}.baseimg.tpl || true
    docker export ${type}-${arch}.baseimg | mksquashfs - ${type}-${arch}.baseimg.tpl -tar # -quiet
    docker rm -v ${type}-${arch}.baseimg
    log "Pre chroot, copy files in ${type}-${arch}/docker/"
    dpkg -x nginx-johnyin_${arch}.deb ${type}-${arch}/docker
    sed -i "s/^user .*;/user ${username} ${username};/g"  ${type}-${arch}/docker/etc/nginx/nginx.conf
    sed -i "s/worker_processes .*;/worker_processes 1;/g" ${type}-${arch}/docker/etc/nginx/nginx.conf
    sed -i "/worker_priority/d"                           ${type}-${arch}/docker/etc/nginx/nginx.conf
    mkdir -p ${type}-${arch}/docker/app && {
        tar -C ${type}-${arch}/docker/app -xf ${SOURCE_DIR}/novnc.tgz
        tar -C ${type}-${arch}/docker/app -xf ${SOURCE_DIR}/spice.tgz --transform 's/^spice.*master/spice/'
        # tar -C ${type}-${arch}/docker/app --one-top-level=spice --strip-components 1 -xf ${SOURCE_DIR}/spice.tgz
        tar -C ${SOURCE_DIR} -c ui term | tar -C ${type}-${arch}/docker/app -x
        for fn in ${SOURCE_DIR}/*.py; do
            $(which cp) -f ${fn} ${type}-${arch}/docker/app/
        done
        $(which cp) -f ${SOURCE_DIR}/database.py.shm ${type}-${arch}/docker/app/database.py
        chown -R 10001:10001 ${type}-${arch}/docker/app
    }
    log "Pre chroot exit"
    ./tpl_overlay.sh -t ${type}-${arch}.baseimg.tpl -r ${type}-${arch}.rootfs --upper ${type}-${arch}/docker
    log "chroot ${type}-${arch}.rootfs,(copy app) exit continue build"
    chroot ${type}-${arch}.rootfs /usr/bin/env -i SHELL=/bin/bash PS1="\u@DOCKER-${arch}:\w$" TERM=${TERM:-} COLORTERM=${COLORTERM:-} /bin/bash --noprofile --norc -o vi || true
    log "exit ${type}-${arch}.rootfs"
    ./tpl_overlay.sh -r ${type}-${arch}.rootfs -u
    log "Post chroot, delete nouse file in ${type}-${arch}/docker/"
    for fn in tmp run root build.run nginx-johnyin_${arch}.deb; do
        rm -fr ${type}-${arch}/docker/${fn}
    done
    rm -vfr ${type}-${arch}.baseimg.tpl ${type}-${arch}.rootfs
done
log '=================================================='
for arch in ${ARCH[@]}; do
    log docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    log ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/libvirtd/${type}:${ver}-${arch}
    log docker push ${REGISTRY}/libvirtd/${type}:${ver}-${arch}
done
log ./make_docker_image.sh -c combine --tag ${REGISTRY}/libvirtd/${type}:${ver}

trap "exit -1" SIGINT SIGTERM
read -n 1 -t 10 -p "Continue build(Y/n)? 10s timeout, default n" value || true
if [ "${value}" = "y" ]; then
    for arch in ${ARCH[@]}; do
        docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
        ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/libvirtd/${type}:${ver}-${arch}
        docker push ${REGISTRY}/libvirtd/${type}:${ver}-${arch}
    done
    ./make_docker_image.sh -c combine --tag ${REGISTRY}/libvirtd/${type}:${ver}
fi
cat <<EOF
###################################################
# test run
###################################################
# # when: qemu+ssh://, actions add template disk
#     chown -R 10001:10001 /kvm/ssh
#     chmod 700            /kvm/ssh
#     -v /kvm/ssh:/home/${username}/.ssh/
#        id_rsa id_rsa.pub config
# # when: qemu+tls://
#     -v /kvm/pki:/etc/pki/
#        CA/cacert.pem libvirt/clientcert.pem libvirt/private/clientkey.pem
# #   -v /host/ssl:/etc/nginx/ssl
#        simplekvm.key simplekvm.pem
docker pull ${REGISTRY}/libvirtd/${type}:${ver} --platform amd64
# # need http  get hosts define in golds.json when add disk with template (api srv)
# # need https get host META_SRV for metadata and iso cdrom file (kvm srv)

GOLD_SRV=vmm.registry.local
gold_srv_ipaddr=192.168.167.1

docker run --rm \\
 --name vmmgr-api \\
 --restart always \\
 --network br-int --ip 192.168.169.123 \\
 --env LEVELS='{"main":"INFO"}' \\
 --env META_SRV=vmm.registry.local \\
 --env GOLD_SRV=\${GOLD_SRV} --add-host \${GOLD_SRV}:\${gold_srv_ipaddr} \\
 --env ETCD_SRV=192.168.169.1 \\
 --env ETCD_PORT=2379 \\
 -v /host/pki:/etc/pki/ \\
 -v /host/ssl:/etc/nginx/ssl \\
 -v /host/ssh:/home/simplekvm/.ssh \\
 ${REGISTRY}/libvirtd/${type}:${ver}
EOF

cat <<EOF
# # /home/simplekvm/.ssh/config
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
ControlMaster auto
ControlPath  ~/.ssh/%r@%h:%p
ControlPersist 600
Ciphers aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha1
EOF
