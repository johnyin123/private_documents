#!/usr/bin/env bash
TPL_FILE=${1:?$(echo "input tpl file"; exit 1;)}
ROOTFS=rootfs
mkdir -p ${ROOTFS} && {
    ./tpl_overlay.sh -t ${TPL_FILE} -r ${ROOTFS}
cat <<EOF
yum -y install qemu-guest-agent cloud-init cloud-utils-growpart sudo
systemctl enable qemu-guest-agent cloud-init
EOF
    ./chroot.sh ${ROOTFS}
}
fname=(/usr/share/info
/usr/share/lintian
/usr/share/linda 
/var/cache/yum
/var/tmp/yum-*
/var/lib/yum/*
/root/.rpmdb
/root/.bash_history
/root/.lesshst
/root/.viminfo
/root/.vim/
/var/cache/apt/*
/var/lib/apt/lists/*
/var/cache/debconf/*-old
/var/lib/dpkg/*-old
/root/.bash_history
/root/.lesshst
/root/.viminfo
/root/.vim/)
for fn in ${fname[@]}; do
    rm -vrf ${ROOTFS}/${fn} || true
done
find ${ROOTFS}/var/log/ -type f | xargs truncate -s0
find ${ROOTFS}/usr/share/doc -depth -type f ! -name copyright -print0 | xargs -0 rm || true
find ${ROOTFS}/usr/share/doc -empty -print0 | xargs -0 rm -rf || true
# remove on used locale
find ${ROOTFS}/usr/share/locale -maxdepth 1 -mindepth 1 -type d ! -iname 'zh_CN*' ! -iname 'en*' | xargs -I@ rm -rf @ || true

./tpl_pack.sh -c xz ${ROOTFS} ${TPL_FILE}.new
./tpl_overlay.sh -u -r ${ROOTFS}
rm -rf ${ROOTFS}
