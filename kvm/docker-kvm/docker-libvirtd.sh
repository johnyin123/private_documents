#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
file_exists() { [ -e "$1" ]; }
ARCH=(amd64 arm64)

type=kvm
ver=trixie

for fn in make_docker_image.sh tpl_overlay.sh; do
    file_exists "${fn}" || { log "${fn} no found"; exit 1; }
done

export BUILD_NET=${BUILD_NET:-br-int}
export REGISTRY=registry.local
export IMAGE=debian:trixie       # # BASE IMAGE
export NAMESPACE=
declare -A PKGS=(
    [amd64]="qemu-system-x86 ovmf"
    [arm64]="qemu-system-arm qemu-efi-aarch64"
)

for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    cat <<EODOC > ${type}-${arch}/docker/build.run
set -o nounset -o pipefail -o errexit
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
APT="apt -y ${PROXY:+--option Acquire::http::Proxy=\"${PROXY}\" }--no-install-recommends"
\${APT} update && \${APT} install supervisor libvirt-daemon \\
    libvirt-daemon-lock libvirt-daemon-log \\
    libvirt-daemon-driver-qemu libvirt-daemon-driver-storage-rbd \\
    libvirt-daemon-system ${PKGS[${arch}]} \\
    qemu-block-extra qemu-utils \\
    iproute2 bridge-utils
    # curl
    rm -fr /etc/libvirt/qemu/* || true
    sed --quiet -i -E \\
        -e '/^\s*(user|spice_tls|spice_tls_x509_cert_dir|vnc_tls|vnc_tls_x509_cert_dir|vnc_tls_x509_verify)\s*=.*/!p' \\
        /etc/libvirt/qemu.conf || true

   # # spice & libvirt use same tls key/cert/ca files
   sed --quiet -i.orig -E \\
         -e '/^\s*(ca_file|cert_file|key_file|listen_addr|listen_tls|tcp_port).*/!p' \\
         -e '\$aca_file = "/etc/libvirt/pki/ca-cert.pem"' \\
         -e '\$acert_file = "/etc/libvirt/pki/server-cert.pem"' \\
         -e '\$akey_file = "/etc/libvirt/pki/server-key.pem"' \\
         -e '\$alisten_tcp = 1' \\
         -e '\$alisten_tls = 1' \\
         -e '\$alisten_addr = "0.0.0.0"' \\
         -e '\$a#tcp_port = "16509"' \\
         /etc/libvirt/libvirtd.conf

find /usr/share/locale -maxdepth 1 -mindepth 1 -type d ! -iname 'zh_CN*' ! -iname 'en*' | xargs -I@ rm -rf @ || true
rm -rf /var/lib/apt/* /var/cache/* /root/.cache /root/.bash_history /usr/share/man/* /usr/share/doc/*
EODOC
    mkdir -p ${type}-${arch}/docker/ && cat <<'EODOC' >${type}-${arch}/docker/entrypoint.sh
#!/bin/bash
gid=$(stat --printf=%g /dev/kvm)
groupmod --non-unique -g ${gid} kvm
echo "execute libvirtd ${gid}"
echo "Running entrypoint setup..."
env || true
exec "$@"
EODOC
    chmod 755 ${type}-${arch}/docker/entrypoint.sh
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:libvirtd]
command=/usr/sbin/libvirtd --listen
autostart=true
autorestart=true
startretries=5
user=root
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:virtlockd]
command=/usr/sbin/virtlockd
autostart=true
autorestart=true
startretries=5
user=root
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:virtlogd]
command=/usr/sbin/virtlogd
autostart=true
autorestart=true
startretries=5
user=root
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC
    cat <<EODOC >> ${type}-${arch}/Dockerfile
# need /sys/fs/cgroup
VOLUME ["/sys/fs/cgroup", "/etc/libvirt/qemu", "/etc/libvirt/secrets", "/var/run/libvirt", "/var/lib/libvirt", "/var/log/libvirt", "/etc/libvirt/pki", "/storage"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisord.conf"]
EODOC
    # confirm base-image is right arch
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --name ${type}-${arch}.baseimg --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m || true
    rm -f ${type}-${arch}.baseimg.tpl || true
    docker export ${type}-${arch}.baseimg | mksquashfs - ${type}-${arch}.baseimg.tpl -tar # -quiet
    docker rm -v ${type}-${arch}.baseimg
    log "Pre chroot, copy files in ${type}-${arch}/docker/"
    log "Pre chroot exit"
    ./tpl_overlay.sh -t ${type}-${arch}.baseimg.tpl -r ${type}-${arch}.rootfs --upper ${type}-${arch}/docker
    log "chroot ${type}-${arch}.rootfs, exit continue build"
    chroot ${type}-${arch}.rootfs /usr/bin/env -i SHELL=/bin/bash PS1="\u@DOCKER-${arch}:\w$" TERM=${TERM:-} COLORTERM=${COLORTERM:-} /bin/bash --noprofile --norc -o vi || true
    log "exit ${type}-${arch}.rootfs"
    ./tpl_overlay.sh -r ${type}-${arch}.rootfs -u
    log "Post chroot, delete nouse file in ${type}-${arch}/docker/"
    for fn in tmp run root build.run; do
        rm -fr ${type}-${arch}/docker/${fn}
    done
    rm -vfr ${type}-${arch}.baseimg.tpl ${type}-${arch}.rootfs
done
log '=================================================='
for arch in ${ARCH[@]}; do
    log docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    log ./make_docker_image.sh -c build -D ${type}-${arch} --tag registry.local/libvirtd/${type}:${ver}-${arch}
    log docker push registry.local/libvirtd/${type}:${ver}-${arch}
done
log ./make_docker_image.sh -c combine --tag registry.local/libvirtd/${type}:${ver}
cat <<'EOF'
###################################################
# test run
###################################################
# # ceph rbd/local storage/net bridge all ok, arm64 ok
# # default pool /lib/libvirt/images
# # host machine need socat, for vnc/spice !!
# # #######################################
yum / apt install socat docker
libvirtd_env=/libvirtd_env
for dir in log vms pki secrets run/libvirt lib/libvirt; do
    mkdir -p "${libvirtd_env}/${dir}"
done
mkdir -p /storage
META_SRV=vmm.registry.local
meta_srv_addr=192.168.167.1
hostname=${NAME:-$(hostname)}
docker create --name libvirtd \\
    --hostname ${hostname} \\
    --add-host ${hostname}:127.0.0.1 \\
    --network host \\
    --restart always \\
    --privileged \\
    --device /dev/kvm \\
    --add-host ${META_SRV}:${meta_srv_addr} \\
    -v ${libvirtd_env}/pki:/etc/libvirt/pki \\
    -v /storage:/storage \\
    registry.local/libvirtd/kvm:trixie

    # -v ${libvirtd_env}/log:/var/log/libvirt \\
    # -v ${libvirtd_env}/vms:/etc/libvirt/qemu \\
    # -v ${libvirtd_env}/secrets:/etc/libvirt/secrets \\
    # -v ${libvirtd_env}/run/libvirt:/var/run/libvirt \\
    # -v ${libvirtd_env}/lib/libvirt:/var/lib/libvirt \\
# # #######################################
YEAR=15 ./newssl.sh -i johnyinca
YEAR=15 ./newssl.sh -c vmm.registry.local # # meta-iso web service use
YEAR=15 ./newssl.sh -c cli                # # virsh client
# # kvm servers
YEAR=15 ./newssl.sh -c kvm1.local --ip 192.168.168.1 --ip 192.168.169.1
# # #######################################
# # init server
# cp ca/kvm1.local.pem /${libvirtd_env}/pki/server-cert.pem
# cp ca/kvm1.local.key /${libvirtd_env}/pki/server-key.pem
# cp ca/ca.pem         /${libvirtd_env}/pki/ca-cert.pem
# # # server-key.pem, MUST CAN READ BY QEQMU PROCESS(chown)
# chmod 440 /etc/libvirt/pki/*
# chown root.qemu /etc/libvirt/pki/*
# # #######################################
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
virsh -c qemu+unix:///system?socket=/vmmgr/run/libvirt/libvirt-sock
virsh -c qemu+tls://192.168.168.1/system list --all
virsh -c qemu+tls://kvm1.local/system list --all
virsh -c qemu+ssh://root@192.168.168.1:60022/system?socket=/vmmgr/run/libvirt/libvirt-sock
# <graphics type='spice' tlsPort='-1' autoport='yes' listen='0.0.0.0' defaultMode='secure'/>
# <graphics type='vnc' autoport='yes' listen='0.0.0.0'/>
remote-viewer --spice-ca-file=~/.pki/libvirt/cacert.pem spice://127.0.0.1?tls-port=5906
EOF

: <<EOF
# # change (kvm) gid to HOST kvm gid
# # /etc/libvirt/qemu.conf maybe no need user=root
groupmod -n NEW_GROUP_NAME OLD_GROUP_NAME).
groupmod -g NEWGID GROUPNAME
EOF
