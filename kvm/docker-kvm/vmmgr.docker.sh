#!/usr/bin/env bash

export BUILD_NET=br-int
export IMAGE=debian:bookworm
export REGISTRY=registry.local
export NAMESPACE=
ARCH=(amd64) # arm64)
type=vmmgr
ver=bookworm

username=johnyin
files=(config.py dbi.py flask_app.py meta.py utils.py database.py device.py main.py template.py vmmanager.py ipaddress.py console.py)
for fn in ${files[@]}; do
    [ -e "${fn}" ] || { echo "${fn}, nofound"; exit 1;}
done
OUTDIR=/work
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    install -v -d -m 0755 "${type}-${arch}/docker/home/${username}"
    for fn in ${files[@]}; do
        install -v -C -m 0644 --group=10001 --owner=10001 "${fn}" "${type}-${arch}/docker/home/${username}/${fn}"
    done
    echo "console.py need 755"
    chmod 755 "${type}-${arch}/docker/home/${username}/console.py"
    cat <<EODOC > ${type}-${arch}/docker/build.run
useradd -u 10001 -m ${username} --home-dir /home/${username}/ --shell /bin/bash
apt -y --no-install-recommends update
echo "need socat,qemu-img"
apt -y --no-install-recommends install socat qemu-utils supervisor python3 python3-venv
apt -y --no-install-recommends install websockify python3-websockify \
    python3-flask python3-pycdlib python3-libvirt \
    python3-sqlalchemy gunicorn python3-gunicorn
EODOC
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root

[program:webapp]
command=gunicorn --env DATABASE="\${DATABASE:-sqlite:///${OUTDIR}/kvm.db}" --env OUTDIR='${OUTDIR}' -b 0.0.0.0:5009 --preload --workers=2 --threads=2 --error-logfile='-' --access-logfile='-' main:app
user=${username}
directory=/home/${username}/
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:websockify]
command=websockify --token-plugin TokenFile --token-source ${OUTDIR}/token/ 0.0.0.0:6800
user=${username}
directory=/home/${username}/
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
VOLUME ["${OUTDIR}", "/etc/pki"]
ENTRYPOINT ["/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisord.conf"]
EODOC
    ################################################
    # confirm base-image is right arch
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --rm --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m
    ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/libvirtd/${type}:${ver}-${arch}
    docker push ${REGISTRY}/libvirtd/${type}:${ver}-${arch}
done
./make_docker_image.sh -c combine --tag ${REGISTRY}/libvirtd/${type}:${ver}

cat <<'EOF'
PKI_DIR=/etc/pki
${PKI_DIR}/CA/cacert.pem
${PKI_DIR}/libvirt/private/clientkey.pem
${PKI_DIR}/libvirt/clientcert.pem

HOST_DIR=/home/johnyin/testvmm
mkdir -p ${HOST_DIR}/iso
mkdir -p ${HOST_DIR}/gold
mkdir -p ${HOST_DIR}/actions
mkdir -p ${HOST_DIR}/devices
mkdir -p ${HOST_DIR}/domains
mkdir -p ${HOST_DIR}/meta
mkdir -p ${HOST_DIR}/token
mkdir -p ${HOST_DIR}/nocloud
mkdir -p ${HOST_DIR}/request
# first init ${HOST_DIR}/kvm.db
EOF
cat <<EOF
docker run --rm \
    --network br-int --ip 192.168.169.123 \
    --env DATABASE=sqlite:///${OUTDIR}/kvm.db \
    -v \${HOST_DIR}:${OUTDIR} \
    -v /etc/pki:/etc/pki \
    ${REGISTRY}/libvirtd/${type}:${ver}
EOF
