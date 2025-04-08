#!/usr/bin/env bash

export BUILD_NET=br-int
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
        /etc/libvirt/qemu.conf || true
        # -e "\$auser = \"root\"" \

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
    mkdir -p ${type}-${arch}/docker/usr/sbin/ && cat <<'EODOC' >${type}-${arch}/docker/usr/sbin/libvirtd.wrap
#!/usr/bin/bash
gid=$(stat --printf=%g /dev/kvm)
groupmod --non-unique -g ${gid} kvm
echo "execute libvirtd ${gid}"
exec /usr/sbin/libvirtd --listen
EODOC
    chmod 755 ${type}-${arch}/docker/usr/sbin/libvirtd.wrap
    mkdir -p ${type}-${arch}/docker/etc && cat <<EODOC > ${type}-${arch}/docker/etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
[program:libvirtd]
command=/usr/sbin/libvirtd.wrap
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

# # ceph rbd/local storage/net bridge all ok, arm64 ok
# # volume /storage: use defined local dir storage
# # default pool /storage/lib/libvirt/images
# -v /storage:/storage \
# # host machine need socat, for vnc/spice !!
yum / apt install socat
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
    registry.local/libvirtd/${type}:${ver}

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
