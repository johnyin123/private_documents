#!/usr/bin/env bash

export BUILD_NET=br-ext
export IMAGE=debian:bookworm
export REGISTRY=registry.local
export NAMESPACE=
ARCH=(amd64 arm64)
type=kvm
ver=bookworm
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    cat <<EODOC > ${type}-${arch}/docker/build.run
apt update && apt -y --no-install-recommends install \
    supervisor \
    libvirt-daemon \
    libvirt-daemon-driver-qemu \
    libvirt-daemon-driver-storage-rbd \
    libvirt-daemon-system \
    libvirt-clients \
    ovmf qemu-efi-aarch64 \
    qemu-system-arm \
    qemu-system-x86 \
    qemu-block-extra \
    qemu-utils \
    iproute2 bridge-utils
    rm -fr /etc/libvirt/qemu/* || true
    sed --quiet -i -E \
        -e '/^\s*(user)\s*=.*/!p' \
        -e "\\\$auser = \"root\"" \
        /etc/libvirt/qemu.conf || true
EODOC
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
[program:libvirtd]
command=/usr/sbin/libvirtd
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
[program:virtlockd]
command=/usr/sbin/virtlockd
[program:virtlogd]
command=/usr/sbin/virtlogd
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
# need /sys/fs/cgroup
VOLUME ["/sys/fs/cgroup", "/etc/libvirt/qemu", "/etc/libvirt/secrets", "/var/run/libvirt/", "/var/lib/libvirt", "/var/log/libvirt"]
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
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X

# cehp rbd/local storage/net bridge all ok, arm64 ok
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
    -v /storage/secrets:/etc/libvirt/secrets \
    -v /storage/run/libvirt:/var/run/libvirt \
    -v /storage/lib/libvirt:/var/lib/libvirt \
    registry.local/libvirtd/kvm:${ver}

virsh -c qemu+unix:///system?socket=/storage/run/libvirt/libvirt-sock
EOF

type=libvirt-client
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    cat <<EODOC > ${type}-${arch}/docker/build.run
apt update && apt -y --no-install-recommends install openssh-server libvirt-clients netcat-openbsd
mkdir -p /run/sshd/
EODOC
    # confirm base-image is right arch
    docker pull --quiet registry.local/debian:bookworm --platform ${arch}
    docker run --rm --entrypoint="uname" registry.local/debian:bookworm -m
    ./make_docker_image.sh -c build -D ${type}-${arch} --tag registry.local/libvirtd/${type}:${ver}-${arch}
    docker push registry.local/libvirtd/${type}:${ver}-${arch}
done
./make_docker_image.sh -c combine --tag registry.local/libvirtd/${type}:${ver}

cat <<EOF
network=host # or other networks
docker create --name ctrl \
    --network \${network} \
    --volumes-from libvirtd \
    -v /root/.ssh/:/root/.ssh \
    registry.local/libvirtd/libvirt-client:${ver} \
    /usr/sbin/sshd -D -p9999
# # -p 8888:9999
virsh -c qemu+ssh://root@10.170.24.5:9999/system
EOF

export IMAGE=nginx:bookworm
type=meta-iso
username=johnyin
[ -e "flask_app.py" ] && [ -e "iso.py" ] || { echo "flask_app.py iso.py, nofound"; exit 1;}
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    mkdir -p ${type}-${arch}/docker/home/${username}/ && {
        cp flask_app.py iso.py ${type}-${arch}/docker/home/${username}/
        chown -R 10001:10001 ${type}-${arch}/docker/home/${username}/
    }
    mkdir -p ${type}-${arch}/docker/etc/nginx/http-enabled && \
    cat <<'EOF' > ${type}-${arch}/docker/etc/nginx/http-enabled/site.conf
upstream flask_app {
    server 127.0.0.1:5009 fail_timeout=0;
}
server {
    listen 80;
    # listen 443 ssl;
    # ssl_certificate     /etc/nginx/ssl/ngxsrv.pem;
    # ssl_certificate_key /etc/nginx/ssl/ngxsrv.key;
    # ssl_client_certificate /etc/nginx/ssl/ca.pem;
    server_name _;
    location ~* /create/(.*) {
        set $key $1;
        satisfy any;
        allow 172.16.0.0/21;
        allow 192.168.168.0/24;
        deny all;
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/kvm.htpasswd;
        proxy_buffering                    off;
        proxy_request_buffering            off;
        client_max_body_size 10m;
        if ($request_method !~ ^(POST)$) { return 405 "Only POST"; }
        proxy_pass http://flask_app/$key;
    }
    location / {
        # disable checking of client request body size
        client_max_body_size 10m;
        autoindex off;
        root /iso;
    }
}
EOF
    printf "admin:$(openssl passwd -apr1 KVMP@ssW0rd)\n" > ${type}-${arch}/docker/etc/nginx/kvm.htpasswd
    cat <<EODOC > ${type}-${arch}/docker/build.run
useradd -u 10001 -m ${username} --home-dir /home/${username}/ --shell /bin/bash
apt -y --no-install-recommends update
apt -y --no-install-recommends install python3 python3-venv \
    supervisor \
    python3-flask python3-pycdlib \
    gunicorn python3-gunicorn
EODOC
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root

[program:nginx]
command=/bin/bash -c "chown -R johnyin:johnyin /iso; sed -i '/worker_processes/d' /etc/nginx/nginx.conf; nginx -c /etc/nginx/nginx.conf -g 'daemon off;'"
numprocs=1
autostart=true
autorestart=true
startsecs=0
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0

[program:webapp]
command=gunicorn -b 127.0.0.1:5009 iso:app
directory=/home/${username}/
environment=LOG=DEBUG, OUTDIR="/iso"
autostart=true
autorestart=true
user=johnyin
redirect_stderr=true
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
VOLUME ["/iso"]
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

# {
#     'ipaddr': '',
#     'gateway': '',
#     'uuid': 'uri',
#     'rootpass': 'password',
#     'hostname': 'vmsrv',
#     'interface': 'eth0'
# }
# docker run --rm  --network br-ext registry.local/libvirtd/meta-iso:bookworm
# curl -u admin:KVMP@ssW0rd -X POST http://192.168.169.192/disk/vm1 -d '{"ipaddr":"1.2.3.4/5", "gateway":"gw"}'
