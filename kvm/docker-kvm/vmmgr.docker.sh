#!/usr/bin/env bash

export BUILD_NET=br-int
export IMAGE=debian:bookworm
export REGISTRY=registry.local
export NAMESPACE=
ARCH=(amd64 arm64)
type=vmmgr
ver=bookworm-$(date '+%Y%m%d%H%M%S')
username=johnyin
OUTDIR=/work
files=(config.py dbi.py flask_app.py meta.py utils.py database.py device.py main.py template.py vmmanager.py ipaddress.py console.py)
for fn in ${files[@]}; do
    [ -e "${fn}" ] || { echo "${fn}, nofound"; exit 1;}
done
for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    install -v -d -m 0755 "${type}-${arch}/docker/app"
    for fn in ${files[@]}; do
        install -v -C -m 0644 --group=10001 --owner=10001 "${fn}" "${type}-${arch}/docker/app/${fn}"
    done
    echo "console.py need 755"
    chmod 755 "${type}-${arch}/docker/app/console.py"
    cat <<EODOC > ${type}-${arch}/docker/build.run
useradd -u 10001 -m ${username} --home-dir /home/${username}/ --shell /bin/bash
apt -y --no-install-recommends update
echo "need jq,socat,qemu-img(qemu-block-extra),ssh(libvirt open)" # libvirt-clients
apt -y --no-install-recommends install jq openssh-client socat qemu-utils qemu-block-extra supervisor python3 python3-venv
apt -y --no-install-recommends install websockify python3-websockify \
    python3-flask python3-pycdlib python3-libvirt \
    python3-sqlalchemy gunicorn python3-gunicorn
    rm -fr /etc/pki && ln -s /home/${username}/pki /etc/pki
EODOC
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root

[program:webapp]
command=gunicorn --env OUTDIR='${OUTDIR}' -b 0.0.0.0:5009 --preload --workers=2 --threads=2 --error-logfile='-' --access-logfile='-' main:app
user=${username}
directory=/app
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:websockify]
command=websockify --token-plugin TokenFile --token-source ${OUTDIR}/token/ 0.0.0.0:6800
user=${username}
directory=/app
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
VOLUME ["${OUTDIR}", "/home/${username}"]
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
#!/usr/bin/env bash
HOME_DIR=/home/johnyin/testvmm/home
HOST_DIR=/home/johnyin/testvmm/vmmgr
[ "$(id -u)" -eq 0 ] || { echo "root need!"; exit 1; }
dirs=(actions devices domains meta)
files=(cacert.pem clientkey.pem clientcert.pem id_rsa id_rsa.pub kvm.db)
cat <<EO_DOC>config
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
Host *
    ControlMaster auto
    ControlPath /tmp/vmmgr-%r@%h-%p
    ControlPersist 600
    Ciphers aes256-ctr,aes192-ctr,aes128-ctr
    MACs hmac-sha1
EO_DOC
echo "dir(${dirs[@]}) file(${files[@]})"
for dn in ${dirs[@]}; do
    [ -d "${dn}" ] || { echo "${dn} directory, nofound"; exit 1;}
done
for fn in ${files[@]}; do
    [ -e "${fn}" ] || { echo "${fn} file, nofound"; exit 1;}
done
install -v -d -m 0755 --group=10001 --owner=10001 ${HOME_DIR}
install -v -d -m 0755 ${HOME_DIR}/pki/CA
install -v -d -m 0755 ${HOME_DIR}/pki/libvirt/private
install -v -C -m 0644 cacert.pem ${HOME_DIR}/pki/CA/cacert.pem
install -v -C -m 0644 clientkey.pem ${HOME_DIR}/pki/libvirt/private/clientkey.pem
install -v -C -m 0644 clientcert.pem ${HOME_DIR}/pki/libvirt/clientcert.pem
install -v -d -m 0700 --group=10001 --owner=10001 ${HOME_DIR}/.ssh && {
    install -v -C -m 0600 --group=10001 --owner=10001 id_rsa ${HOME_DIR}/.ssh/id_rsa
    install -v -C -m 0644 --group=10001 --owner=10001 id_rsa.pub ${HOME_DIR}/.ssh/id_rsa.pub
    install -v -C -m 0644 --group=10001 --owner=10001 config ${HOME_DIR}/.ssh/config
}
# HOST_DIR must owner 10001, so kvm.db can write!!
install -v -d -m 0755 --group=10001 --owner=10001 ${HOST_DIR}
install -v -d -m 0755 --group=10001 --owner=10001 ${HOST_DIR}/iso
install -v -d -m 0755 --group=10001 --owner=10001 ${HOST_DIR}/gold
install -v -d -m 0755 --group=10001 --owner=10001 ${HOST_DIR}/token
install -v -d -m 0755 --group=10001 --owner=10001 ${HOST_DIR}/nocloud
install -v -d -m 0755 --group=10001 --owner=10001 ${HOST_DIR}/request
install -v -C -m 0644 --group=10001 --owner=10001 kvm.db ${HOST_DIR}/kvm.db

##inst tpl config files, dir maybe can readonly?
for dn in ${dirs[@]}; do
    install -v -d -m 0755 --group=10001 --owner=10001 ${HOST_DIR}/${dn}
    for fn in ${dn}/*; do
        echo "install ${fn}"
        mode=0644
        [ "${dn}" == "actions" ] && mode=0755
        install -v -C -m ${mode} --group=10001 --owner=10001 ${fn} ${HOST_DIR}/${fn}
    done
done
EOF
cat <<EOF
docker run --rm \\
    --name vmmgr \\
    --network br-int --ip 192.168.169.123 \\
    --env DATABASE=sqlite:///${OUTDIR}/kvm.db \\
    -v \${HOST_DIR}:${OUTDIR} \\
    -v \${HOME_DIR}:/home/${username} \\
    ${REGISTRY}/libvirtd/${type}:${ver}
EOF
