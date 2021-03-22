#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("mkcentos.sh - initversion - 2021-03-22T09:15:57+08:00")
################################################################################
RELEASE_VER=7.9.2009
ROOTFS=${DIRNAME}/buildroot

mkdir -p ${ROOTFS}

cat <<'EOF' > ${DIRNAME}/centos.conf
[centos]
name=CentOS-$releasever - Base
baseurl=http://mirrors.163.com/centos/$releasever/os/$basearch/
gpgcheck=0
EOF
echo "initialize rpm database"
rpm --root ${ROOTFS} --initdb
echo "download and install the centos-release package, it contains our repository sources"
yumdownloader -c centos.conf --disablerepo=* --enablerepo=centos  --releasever=${RELEASE_VER} centos-release
rpm --root ${ROOTFS} -ivh --nodeps centos-release*.rpm
rpm --root ${ROOTFS} --import  ${ROOTFS}/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-?
echo "install yum without docs and install only the english language files during the process"
yum -y --installroot=${ROOTFS} --setopt=tsflags='nodocs' --setopt=override_install_langs=en_US.utf8 install yum passwd
[ -e "busybox-x86_64" ] || wget https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64
cp busybox-x86_64 ${ROOTFS}/usr/bin/busybox && chmod 755 ${ROOTFS}/usr/bin/busybox
echo "configure yum to avoid installing of docs and other language files than english generally"
sed -i "/distroverpkg=centos-release/a override_install_langs=en_US.utf8\ntsflags=nodocs" ${ROOTFS}/etc/yum.conf
echo "chroot to the environment and install some additional tools"
cp /etc/resolv.conf ${ROOTFS}/etc
systemd-nspawn -D ${ROOTFS} /bin/bash -s <<EOF
yum install -y openssh-server openssh-clients rsync
yum clean all

[ -e "/etc/ssh/sshd_config" ] && {
    sed -i 's/#UseDNS.*/UseDNS no/g'                   /etc/ssh/sshd_config
    sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g'        /etc/ssh/sshd_config
    sed -i 's/#Port.*/Port 60022/g'                    /etc/ssh/sshd_config
    echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
    echo "MACs    hmac-sha1" >>                        /etc/ssh/sshd_config
    echo "PermitRootLogin yes">>                       /etc/ssh/sshd_config
}
EOF
#initscripts 
