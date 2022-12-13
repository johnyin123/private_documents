rootfs=/root/rootfs
mkdir ${rootfs}
yumdownloader --destdir=. openEuler-release
rpm --root ${rootfs} --initdb
rpm --root ${rootfs} -ivh --nodeps openEuler-release*.rpm
yum -y --installroot=${rootfs} --setopt=tsflags='nodocs' --setopt=override_install_langs=en_US.UTF-8 install glibc zlib

