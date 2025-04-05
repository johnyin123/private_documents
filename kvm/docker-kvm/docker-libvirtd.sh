#!/usr/bin/env bash

export BUILD_NET=br-ext
export IMAGE=debian:bookworm
export REGISTRY=registry.local
export NAMESPACE=
ARCH=(amd64 arm64)
type=kvm
ver=bookworm

[ -e "qemu.hook" ] || { echo "qemu.hook, nofound"; exit 1;}
cat <<EOF
# # change (kvm) gid to HOST kvm gid
# # /etc/libvirt/qemu.conf maybe no need user=root
groupmod -n NEW_GROUP_NAME OLD_GROUP_NAME).
groupmod -g NEWGID GROUPNAME
EOF
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    install -v -d -m 0755 "${type}-${arch}/docker/etc/libvirt/hooks"
    install -v -C -m 0755 "qemu.hook" "${type}-${arch}/docker/etc/libvirt/hooks/qemu"
    cat <<'EODOC' > ${type}-${arch}/docker/build.run
apt update && apt -y --no-install-recommends install \
    supervisor \
    libvirt-daemon \
    libvirt-daemon-driver-qemu \
    libvirt-daemon-driver-storage-rbd \
    libvirt-daemon-system \
    ovmf qemu-efi-aarch64 \
    qemu-system-arm \
    qemu-system-x86 \
    qemu-block-extra \
    qemu-utils \
    iproute2 bridge-utils curl
    rm -fr /etc/libvirt/qemu/* || true
    sed --quiet -i -E \
        -e '/^\s*(user|spice_tls|spice_tls_x509_cert_dir|vnc_tls|vnc_tls_x509_cert_dir|vnc_tls_x509_verify)\s*=.*/!p' \
        -e "\$auser = \"root\"" \
        /etc/libvirt/qemu.conf || true

        # -e '$aspice_tls = 1' \
        # -e '$aspice_tls_x509_cert_dir = "/etc/libvirt/pki/"' \
        # -e '$avnc_tls = 1' \
        # -e '$avnc_tls_x509_cert_dir = "/etc/libvirt/pki/"' \
        # -e '$avnc_tls_x509_verify = 1' \

   # # spice & libvirt use same tls key/cert/ca files
   sed --quiet -i.orig -E \
         -e '/^\s*(ca_file|cert_file|key_file|listen_addr|listen_tls|tcp_port).*/!p' \
         -e '$aca_file = "/etc/libvirt/pki/ca-cert.pem"' \
         -e '$acert_file = "/etc/libvirt/pki/server-cert.pem"' \
         -e '$akey_file = "/etc/libvirt/pki/server-key.pem"' \
         -e '$alisten_tcp = 1' \
         -e '$alisten_tls = 1' \
         -e '$alisten_addr = "0.0.0.0"' \
         -e '$a#tcp_port = "16509"' \
         /etc/libvirt/libvirtd.conf
EODOC
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
[program:libvirtd]
command=/usr/sbin/libvirtd --listen
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
[program:virtlockd]
command=/usr/sbin/virtlockd
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
[program:virtlogd]
command=/usr/sbin/virtlogd
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
# need /sys/fs/cgroup
VOLUME ["/sys/fs/cgroup", "/etc/libvirt/qemu", "/etc/libvirt/secrets", "/var/run/libvirt", "/var/lib/libvirt", "/var/log/libvirt", "/etc/libvirt/pki", "/storage"]
ENTRYPOINT ["/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisord.conf"]
EODOC
    # confirm base-image is right arch
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --rm --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m
    ./make_docker_image.sh -c build -D ${type}-${arch} --tag registry.local/libvirtd/${type}:${ver}-${arch}
    docker push registry.local/libvirtd/${type}:${ver}-${arch}
done
./make_docker_image.sh -c combine --tag registry.local/libvirtd/${type}:${ver}

cat <<EOF
echo '192.168.168.1  kvm.registry.local' >> /etc/hosts

# ceph rbd/local storage/net bridge all ok, arm64 ok
# volume /storage: use defined local dir storage
# -v /storage:/storage \
# default pool /storage/lib/libvirt/images
docker create --name libvirtd \
    --network host \
    --restart always \
    --privileged \
    --device /dev/kvm \
    -v /storage/log:/var/log/libvirt \
    -v /storage/vms:/etc/libvirt/qemu \
    -v /storage/pki:/etc/libvirt/pki \
    -v /storage/secrets:/etc/libvirt/secrets \
    -v /storage/run/libvirt:/var/run/libvirt \
    -v /storage/lib/libvirt:/var/lib/libvirt \
    registry.local/libvirtd/kvm:${ver}

YEAR=15 ./newssl.sh -i johnyinca
YEAR=15 ./newssl.sh -c kvm.registry.local # # meta-iso web service use
YEAR=15 ./newssl.sh -c cli                # # virsh client
# # kvm servers
YEAR=15 ./newssl.sh -c kvm1.local --ip 192.168.168.1 --ip 192.168.169.1
......
# # init server
# cp ca/kvm1.local.pem /storage/pki/server-cert.pem
# cp ca/kvm1.local.key /storage/pki/server-key.pem
# cp ca/ca.pem /storage/pki/ca-cert.pem
# # # server-key.pem, MUST CAN READ BY QEQMU PROCESS(chown)
# chmod 440 /etc/libvirt/pki/*
# chown root.qemu /etc/libvirt/pki/*

# # init client
|----------------------------------------|--------|
| /etc/pki/CA/cacert.pem                 | client |
| /etc/pki/libvirt/private/clientkey.pem | client |
| /etc/pki/libvirt/clientcert.pem        | client |
| ~/.pki/libvirt/cacert.pem              | client |
| ~/.pki/libvirt/clientkey.pem           | client |
| ~/.pki/libvirt/clientcert.pem          | client |
|----------------------------------------|--------|
# sudo install -v -d -m 0755 "/etc/pki/CA/"
# sudo install -v -C -m 0440 "ca/ca.pem" "/etc/pki/CA/cacert.pem"
# mkdir ~/.pki/libvirt
# cp ca/cli.key clientkey.pem ~/.pki/libvirt/
# cp ca/cli.pem clientcert.pem ~/.pki/libvirt/
virsh -c qemu+unix:///system?socket=/storage/run/libvirt/libvirt-sock
virsh -c qemu+tls://192.168.168.1/system list --all
virsh -c qemu+tls://kvm1.local/system list --all
virsh -c qemu+ssh://root@192.168.168.1:60022/system?socket=/storage/run/libvirt/libvirt-sock
# <graphics type='spice' tlsPort='-1' autoport='yes' listen='0.0.0.0' defaultMode='secure'/>
# <graphics type='vnc' autoport='yes' listen='0.0.0.0'/>
remote-viewer --spice-ca-file=~/.pki/libvirt/cacert.pem spice://127.0.0.1?tls-port=5906
EOF

export IMAGE=nginx:bookworm
type=meta-iso
ver=bookworm

username=johnyin
files=(config.py database.py dbi.py device.py exceptions.py flask_app.py main.py template.py vmmanager.py)
for fn in ${files[@]}; do
    [ -e "${fn}" ] || { echo "${fn}, nofound"; exit 1;}
done
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    install -v -d -m 0755 "${type}-${arch}/docker/home/${username}"
    for fn in ${files[@]}; do
        install -v -C -m 0644 --group=10001 --owner=10001 "${fn}" "${type}-${arch}/docker/home/${username}/${fn}"
    done
    OUT_DIR=/work
    mkdir -p ${type}-${arch}/docker/etc/nginx/http-enabled && \
    cat <<'EOF' | sed "s|\${OUT_DIR}|${OUT_DIR}|g" > ${type}-${arch}/docker/etc/nginx/http-enabled/site.conf
server_names_hash_bucket_size 128;
upstream flask_app {
    server 127.0.0.1:5009 fail_timeout=0;
    keepalive 64;
}
upstream websockify {
    # websockify --token-plugin TokenFile --token-source ./token 6800
    server 127.0.0.1:6800;
    keepalive 64;
}
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
server {
    # # OPTIONAL: libvirt upload domain xml hook
    listen 443 ssl;
    server_name kvm.registry.local;
    ssl_certificate     /etc/nginx/ssl/kvm.registry.local.pem;
    ssl_certificate_key /etc/nginx/ssl/kvm.registry.local.key;
    ssl_client_certificate /etc/nginx/ssl/kvm.ca.pem;
    ssl_verify_client on;
    location /domain {
        proxy_buffering                    off;
        proxy_request_buffering            off;
        client_max_body_size 1m;
        if ($request_method !~ ^(POST)$) { return 405 "Only POST"; }
        proxy_set_header X-CERT-DN $ssl_client_s_dn;
        # # need add all other headers, origin was overwrited
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port  $server_port;
        proxy_set_header Origin            $scheme://$host;
        proxy_set_header Host $host;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_pass http://flask_app/domain;
    }
}
map $uri $kvmhost {
    "~*/user/vm/(list|start|stop|display)/(?<name>.*)/(.*)" $name;
}
map $uri $uuid {
    "~*/user/vm/(list|start|stop|display)/(.*)/(?<name>.*)" $name;
}
server {
    listen 80;
    listen 443 ssl;
    server_name vmm.registry.local;
    ssl_certificate     /etc/nginx/ssl/vmm.registry.local.pem;
    ssl_certificate_key /etc/nginx/ssl/vmm.registry.local.key;
    if ($scheme = http ) {
        return 301 https://$server_name$request_uri;
    }
    default_type application/json;
    location ~* .(favicon.ico)$ { access_log off; log_not_found off; add_header Content-Type image/svg+xml; return 200 '<svg width="104" height="104" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="104" height="104" rx="18" fill="url(#a)"/><path fill-rule="evenodd" clip-rule="evenodd" d="M56 26a4.002 4.002 0 0 1-3 3.874v5.376h15a3 3 0 0 1 3 3v23a3 3 0 0 1-3 3h-8.5v4h3a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-21a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2h3v-4H36a3 3 0 0 1-3-3v-23a3 3 0 0 1 3-3h15v-5.376A4.002 4.002 0 0 1 52 22a4 4 0 0 1 4 4zM21.5 50.75a7.5 7.5 0 0 1 7.5-7.5v15a7.5 7.5 0 0 1-7.5-7.5zm53.5-7.5a7.5 7.5 0 0 1 0 15v-15zM46.5 50a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0zm14.75 3.75a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5z" fill="#fff"/><defs><linearGradient id="a" x1="104" y1="0" x2="0" y2="0" gradientUnits="userSpaceOnUse"><stop stop-color="#34C724"/><stop offset="1" stop-color="#62D256"/></linearGradient></defs></svg>'; }
    error_page 403 = @403;
    location @403 { return 403 '{"code":403,"name":"lberr","desc":"Resource Forbidden"}\n'; }
    error_page 404 = @404;
    location @404 { return 404 '{"code":404,"name":"lberr","desc":"Resource not found"}\n'; }
    error_page 405 = @405;
    location @405 { return 405 '{"code":405,"name":"lberr","desc":"Method not allowed"}\n'; }
    error_page 502 = @502;
    location @502 { return 502 '{"code":502,"name":"lberr","desc":"backend server not alive"}\n'; }
    # include /etc/nginx/http-enabled/jwt_sso_auth.inc;
    location / {
        # # default page is guest ui
        return 301 https://$server_name/guest.html;
    }
    location /tpl/ {
        # auth_request @sso-auth;
        # host/device/gold can cached by proxy_cache default
        location ~* ^/tpl/(host|device|gold)/ {
            if ($request_method !~ ^(GET)$ ) { return 405; }
            proxy_pass http://flask_app;
        }
        return 404;
    }
    location /vm/ {
        # auth_request @sso-auth;
        # # no cache!! mgr private access
        proxy_cache off;
        location /vm/stop/ {
            if ($request_method !~ ^(GET|POST)$ ) { return 405; }
            proxy_pass http://flask_app;
        }
        location ~* ^/vm/(list|start|delete|display|xml|ui|freeip)/ {
            if ($request_method !~ ^(GET)$ ) { return 405; }
            proxy_pass http://flask_app;
        }
        location ~* ^/vm/(create|attach_device|detach_device)/ {
            if ($request_method !~ ^(POST)$ ) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://flask_app;
        }
        return 404;
    }
    location = /admin.html {
        # auth_request @sso-auth;
        # # vmmgr ui page, mgr private access
        alias ${OUT_DIR}/ui/tpl.html;
    }
    location ~* ^/ui/.+\.(?:tpl|css|js|otf|eot|svg|ttf|woff|woff2)$ {
        # public access filename ext, other files 404
        autoindex off;
        root ${OUT_DIR};
    }
    location /websockify {
        # # /websockify used by admin & guest ui
        set $websockkey "P@ssw@rd4Display";
        secure_link $arg_k,$arg_e;
        secure_link_md5 "$websockkey$secure_link_expires$arg_token$uri";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_pass http://websockify;
    }
    location  ~* ^/(novnc|spice) {
        # # novnc/spice, pubic access by admin & guest ui
        client_max_body_size 0;
        autoindex off;
        root ${OUT_DIR};
    }
    # # tanent user UI manager tanent vm by uuid
    location = /guest.html {
        # # guest user ui page, guest private access
        alias ${OUT_DIR}/ui/userui.html;
    }
    # # tanent api
    location /user/ {
        # # no cache!! guest user api, guest private access
        proxy_cache off;
        location /user/vm/list/ {
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            if ($request_method !~ ^(GET)$ ) { return 405; }
            proxy_pass http://flask_app/vm/list/;
        }
        location /user/vm/stop/ {
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            if ($request_method !~ ^(GET|POST)$ ) { return 405; }
            proxy_pass http://flask_app/vm/stop/;
        }
        location /user/vm/start/ {
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            if ($request_method !~ ^(GET)$ ) { return 405; }
            proxy_pass http://flask_app/vm/start/;
        }
        location /user/vm/display/ {
            set $userkey "P@ssw@rd4Display";
            secure_link $arg_k,$arg_e;
            secure_link_md5 "$userkey$secure_link_expires$kvmhost$uuid";
            if ($secure_link = "") { return 403; }
            if ($secure_link = "0") { return 410; }
            if ($request_method !~ ^(GET)$ ) { return 405; }
            proxy_pass http://flask_app/vm/display/;
        }
        return 403;
    }
}
# upstream meta_static {
#     server 127.0.0.1:5009 fail_timeout=0;
#     keepalive 64;
# }
server {
    listen 80;
    server_name kvm.registry.local;
    # # only download iso file, and subdir iso
    location ~* \.(iso)$ {
        # rewrite ^ /public/iso$uri break;
        # proxy_pass http://meta_static;
        autoindex off;
        root ${OUT_DIR}/iso;
    }
    # # only download meta-data/user-data and subdir meta-data/user-data
    location ~* \/(meta-data|user-data)$ {
        # rewrite ^ /public/nocloud$uri break;
        # proxy_pass http://meta_static;
        autoindex off;
        root ${OUT_DIR}/nocloud;
    }
}
EOF
    cat <<EODOC > ${type}-${arch}/docker/build.run
useradd -u 10001 -m ${username} --home-dir /home/${username}/ --shell /bin/bash
apt -y --no-install-recommends update
apt -y --no-install-recommends install python3 python3-venv \
    supervisor \
    websockify python3-websockify \
    python3-flask python3-pycdlib python3-libvirt \
    python3-sqlalchemy \
    gunicorn python3-gunicorn
EODOC
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root

[program:nginx]
command=/bin/bash -c "chown -R johnyin:johnyin /iso; sed -i '/worker_processes/d' /etc/nginx/nginx.conf; nginx -c /etc/nginx/nginx.conf -g 'daemon off;'"
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:webapp]
command=gunicorn -b 127.0.0.1:5009 --preload --workers=2 --error-logfile='-' --access-logfile='-' main:app
user=${username}
directory=/home/${username}/
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:websockify]
command=websockify --token-plugin TokenFile --token-source /work/token/ 6800
user=${username}
directory=/home/${username}/
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
VOLUME ["/work", "/etc/nginx/ssl", "/etc/pki"]
ENTRYPOINT ["/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisord.conf"]
EODOC
    ################################################
    # confirm base-image is right arch
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --rm --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m
    ./make_docker_image.sh -c build -D ${type}-${arch} --tag registry.local/libvirtd/${type}:${ver}-${arch}
    docker push registry.local/libvirtd/${type}:${ver}-${arch}
done
./make_docker_image.sh -c combine --tag registry.local/libvirtd/${type}:${ver}

cat <<'EOF'
mkdir -p /storage/pki /storage/ssl /storage/work
for i in iso disk actions devices domains meta token novnc; do
    mkdir -p /storage/work/$i
done

# /storage/work/vminfo.sqlite
# /storage/ssl/kvm.ca.pem;
# /storage/ssl/kvm.registry.local.pem;
# /storage/ssl/kvm.registry.local.key;
# /storage/ssl/vmm.registry.local.pem;
# /storage/ssl/vmm.registry.local.key;
# /storage/pki/CA/cacert.pem
# /storage/pki/libvirt/private/clientkey.pem
# /storage/pki/libvirt/clientcert.pem

docker run --rm \
    --network br-ext --ip 192.168.168.123 \
    --env OUTDIR="/work" \
    --env DATABASE=sqlite:////work/kvm.db \
    -v /storage/work:/work \
    -v /storage/ssl:/etc/nginx/ssl \
    -v /storage/pki:/etc/pki
    registry.local/libvirtd/meta-iso:bookworm

curl --cacert /etc/libvirt/pki/ca-cert.pem \
    --key /etc/libvirt/pki/server-key.pem \
    --cert /etc/libvirt/pki/server-cert.pem \
    -X POST https://kvm.registry.local/domain/prepare/begin/vm1 \
    -F file=@/etc/libvirt/qemu/vm1.xml
EOF
