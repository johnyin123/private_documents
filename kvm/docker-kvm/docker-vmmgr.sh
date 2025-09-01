#!/usr/bin/env bash

export BUILD_NET=br-int
export IMAGE=debian:bookworm
export REGISTRY=registry.local
export NAMESPACE=
ARCH=(amd64 arm64)
type=vmmgr
ver=bookworm
username=johnyin
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    cat <<EODOC > ${type}-${arch}/docker/build.run
useradd -u 10001 -m ${username} --home-dir /home/${username}/ --shell /bin/bash
apt -y --no-install-recommends update
echo "need jq,socat,qemu-img(qemu-block-extra),ssh(libvirt open)" # libvirt-clients
apt -y --no-install-recommends install jq openssh-client socat qemu-utils qemu-block-extra supervisor python3 python3-venv
apt -y --no-install-recommends install websockify python3-websockify \
    python3-flask python3-pycdlib python3-libvirt \
    gunicorn python3-gunicorn python3-etcd3 #python3-sqlalchemy
    rm -fr /etc/pki && ln -s /home/${username}/pki /etc/pki
EODOC
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root

[program:webapp]
command=/home/${username}/app/startup.sh
user=${username}
directory=/home/${username}/app/
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
VOLUME ["/home/${username}"]
ENTRYPOINT ["/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisord.conf"]
EODOC
    ################################################
    # confirm base-image is right arch
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --rm --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m
    ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/libvirtd/${type}:${ver}-${arch}
    docker push ${REGISTRY}/libvirtd/${type}:${ver}-${arch}
done
sleep 4
./make_docker_image.sh -c combine --tag ${REGISTRY}/libvirtd/${type}:${ver}
