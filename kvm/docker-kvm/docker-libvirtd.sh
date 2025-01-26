#!/usr/bin/env bash

export BUILD_NET=br-ext
export IMAGE=debian:bookworm
export REGISTRY=registry.local
export NAMESPACE=
ARCH=(amd64 arm64)
type=kvm
ver=bookworm

[ -e "qemu.hook" ] || { echo "qemu.hook, nofound"; exit 1;}
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
    mkdir -p ${type}-${arch}/docker/etc/nginx/http-enabled && \
    cat <<'EOF' > ${type}-${arch}/docker/etc/nginx/http-enabled/site.conf
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
    listen 443 ssl;
    ssl_certificate     /etc/nginx/ssl/kvm.registry.local.pem;
    ssl_certificate_key /etc/nginx/ssl/kvm.registry.local.key;
    ssl_client_certificate /etc/nginx/ssl/kvm.ca.pem;
    server_name kvm.registry.local;
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
server {
    listen 443 ssl;
    ssl_certificate     /etc/nginx/ssl/vmm.registry.local.pem;
    ssl_certificate_key /etc/nginx/ssl/vmm.registry.local.key;
    server_name vmm.registry.local;
    default_type application/json;
    error_page 404 = @404;
    location @404 { return 404 '{"status":404,"message":"Resource not found"}\n'; }
    error_page 405 = @405;
    location @405 { return 405 '{"status":405,"message":"Method not allowed"}\n'; }
    location /tpl/ {
        location ~* ^/tpl/(host|device|gold) {
            if ($request_method !~ ^(GET)$ ) { return 405; }
            proxy_pass http://flask_app;
        }
        return 404;
    }
    location /vm/ {
        location /vm/stop/ {
            if ($request_method !~ ^(GET|DELETE)$ ) { return 405; }
            proxy_pass http://flask_app;
        }
        location ~* ^/vm/(list|start|delete|display)/ {
            if ($request_method !~ ^(GET)$ ) { return 405; }
            proxy_pass http://flask_app;
        }
        location ~* ^/vm/(create|attach_device)/ {
            if ($request_method !~ ^(POST)$ ) { return 405; }
            proxy_pass http://flask_app;
        }
        return 404;
    }
    location /websockify {
        proxy_pass http://websockify;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
    }
    location /novnc {
        # novnc
        client_max_body_size 0;
        autoindex off;
        root /work;
    }
}
server {
    listen 80;
    server_name kvm.registry.local;
    # # only download iso file, and subdir iso
    location ~* \.(iso)$ {
        client_max_body_size 0;
        autoindex off;
        root /work/iso;
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
command=gunicorn -b 127.0.0.1:5009 --error-logfile='-' --access-logfile='-' main:app
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
