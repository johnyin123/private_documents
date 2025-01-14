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
        -e '/^\s*(user)\s*=.*/!p' \
        -e "\$auser = \"root\"" \
        /etc/libvirt/qemu.conf || true
   sed --quiet -i.orig -E \
         -e '/^\s*(ca_file|cert_file|key_file|listen_addr|listen_tls|tcp_port).*/!p' \
         -e '$aca_file = "/etc/libvirt/pki/ca.pem"' \
         -e '$acert_file = "/etc/libvirt/pki/server.pem"' \
         -e '$akey_file = "/etc/libvirt/pki/server.key"' \
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
VOLUME ["/sys/fs/cgroup", "/etc/libvirt/qemu", "/etc/libvirt/secrets", "/var/run/libvirt", "/var/lib/libvirt", "/var/log/libvirt", "/etc/libvirt/pki"]
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
# cp ca/kvm1.local.pem /storage/pki/server.pem
# cp ca/kvm1.local.key /storage/pki/server.key
# cp ca/ca.pem /storage/pki/ca.pem

# # init client
# sudo install -v -d -m 0755 "/etc/pki/CA/"
# sudo install -v -C -m 0755 "ca/ca.pem" "/etc/pki/CA/cacert.pem"
# mkdir ~/.pki/libvirt
# cp ca/cli.key clientkey.pem ~/.pki/libvirt/
# cp ca/cli.pem clientcert.pem ~/.pki/libvirt/

virsh -c qemu+unix:///system?socket=/storage/run/libvirt/libvirt-sock
virsh -c qemu+tls://192.168.168.1/system list --all
virsh -c qemu+tls://kvm1.local/system list --all
virsh -c qemu+ssh://root@192.168.168.1:60022/system?socket=/storage/run/libvirt/libvirt-sock
EOF

export IMAGE=nginx:bookworm
type=meta-iso
username=johnyin
[ -e "flask_app.py" ] && [ -e "iso.py" ] || { echo "flask_app.py iso.py, nofound"; exit 1;}
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    install -v -d -m 0755 "${type}-${arch}/docker/home/${username}"
    install -v -C -m 0644 --group=10001 --owner=10001 "flask_app.py" "${type}-${arch}/docker/home/${username}/flask_app.py"
    install -v -C -m 0644 --group=10001 --owner=10001 "iso.py" "${type}-${arch}/docker/home/${username}/iso.py"
    mkdir -p ${type}-${arch}/docker/etc/nginx/http-enabled && \
    cat <<'EOF' > ${type}-${arch}/docker/etc/nginx/http-enabled/site.conf
upstream flask_app {
    server 127.0.0.1:5009 fail_timeout=0;
}
server {
    listen 80;
    server_name kvm.registry.local;
    location / {
        # disable checking of client request body size
        client_max_body_size 0;
        autoindex off;
        root /iso;
    }
}
server {
    listen 443 ssl;
    ssl_certificate     /etc/nginx/ssl/kvm.registry.local.pem;
    ssl_certificate_key /etc/nginx/ssl/kvm.registry.local.key;
    ssl_client_certificate /etc/nginx/ssl/ca.pem;
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
EOF
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
VOLUME ["/iso", "/etc/nginx/ssl"]
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
cat <<EOF
docker run --rm \
    --network br-ext \
    -v /storage/iso:/iso \
    -v /storage/pki:/etc/nginx/ssl \
    registry.local/libvirtd/meta-iso:bookworm
curl --cacert ca.pem --key server.key --cert server.pem \
    -X POST https://kvm.registry.local/domain/prepare/begin/vm1 -F file=@/etc/libvirt/qemu/vm1.xml
EOF
