#/bin/bash  


GRUBDEV=/dev/sdb
MOUNTDEV=/dev/sdb1
MOUNTPOINT=/mnt
HOSTNAME=neusoft
NET_DEVICE=eth0
NET_HWADDR=00:E0:4B:2A:3A:9D
NET_IPADDR=172.19.136.1
NET_NETMASK=255.255.255.0
NET_GATEWAY=
TOOLS="busybox"


ROOTDEV=UUID=`blkid -s UUID -o value ${MOUNTDEV}`
FSTYPE=`blkid -s TYPE -o value ${MOUNTDEV}`

if [ $(id -u) != 0 ]; then 
	echo "You need to be root to run this script"
	exit 1
fi

if grep -q "^${MOUNTDEV} " /proc/mounts ; then
	echo "${MOUNTDEV} is mounted"
else
	mount ${MOUNTDEV} ${MOUNTPOINT}
	echo "mount ${MOUNTDEV}"
fi

yum -y install --installroot=${MOUNTPOINT} filesystem
#config fstab
touch ${MOUNTPOINT}/etc/fstab
cat > ${MOUNTPOINT}/etc/fstab << EOF
tmpfs     /dev/shm     tmpfs   defaults        0 0
devpts    /dev/pts     devpts  gid=5,mode=620  0 0
sysfs     /sys         sysfs   defaults        0 0
proc      /proc        proc    defaults        0 0
EOF
echo "${ROOTDEV} / ${FSTYPE}    ro        1 1" >> ${MOUNTPOINT}/etc/fstab

#config mtab
# touch ${MOUNTPOINT}/etc/mtab
ln -s /proc/mounts ${MOUNTPOINT}/etc/mtab
# cat > ${MOUNTPOINT}/etc/mtab << EOF
# none /proc/sys/fs/binfmt_misc binfmt_misc rw 0 0
# proc /proc proc rw 0 0
# sysfs /sys sysfs rw 0 0
# devpts /dev/pts devpts rw,gid=5,mode=620 0 0
# tmpfs /dev/shm tmpfs rw 0 0
# EOF


yum -y install --installroot=${MOUNTPOINT} kernel e2fsprogs passwd ${TOOLS}
#cp /etc/yum.repos.d/local.repo ${MOUNTPOINT}/etc/yum.repos.d/local.repo

#config hostname
echo "NETWORKING=yes" > ${MOUNTPOINT}/etc/sysconfig/network
echo "HOSTNAME=${HOSTNAME}" >> ${MOUNTPOINT}/etc/sysconfig/network
#root can telnet in
cat >> ${MOUNTPOINT}/etc/securetty << EOF
pts/1
pts/2
EOF

#config root .bash_profile
cat > ${MOUNTPOINT}/root/.bash_profile << EOF
# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs
PATH=$PATH:$HOME/bin
export PATH
EOF

#config root .bashrc
cat > ${MOUNTPOINT}/root/.bashrc << EOF
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$"
export LS_OPTIONS='--color=auto'
eval "`dircolors`"
alias ls='ls $LS_OPTIONS -XB'
alias ll='ls $LS_OPTIONS -lhXB'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias df='df -h'
alias du='du -h'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
set -o vi
EOF

grub-install --root-directory=${MOUNTPOINT} ${GRUBDEV}
#config grub.conf
cat > ${MOUNTPOINT}/boot/grub/grub.conf << EOF
default=0
timeout=3
#splashimage=(hd0,0)/boot/grub/splash.xpm.gz
#hiddenmenu
title Linux
	root (hd0,0)
EOF
echo "	kernel /boot/`cd ${MOUNTPOINT}/boot;ls vmlinuz*` selinux=0 ro root=${ROOTDEV}" >> ${MOUNTPOINT}/boot/grub/grub.conf
echo "	initrd /boot/`cd ${MOUNTPOINT}/boot;ls initramfs*`" >> ${MOUNTPOINT}/boot/grub/grub.conf

#change netdev, ipaddr
echo "DEVICE=\"${NET_DEVICE}\"" > ${MOUNTPOINT}/etc/sysconfig/network-scripts/ifcfg-eth0
echo "HWADDR=\"${NET_HWADDR}\"" >> ${MOUNTPOINT}/etc/sysconfig/network-scripts/ifcfg-eth0
echo "ONBOOT=\"yes\"" >> ${MOUNTPOINT}/etc/sysconfig/network-scripts/ifcfg-eth0
echo "BOOTPROTO=static" >> ${MOUNTPOINT}/etc/sysconfig/network-scripts/ifcfg-eth0
echo "IPADDR=${NET_IPADDR}" >> ${MOUNTPOINT}/etc/sysconfig/network-scripts/ifcfg-eth0
echo "NETMASK=${NET_NETMASK}" >> ${MOUNTPOINT}/etc/sysconfig/network-scripts/ifcfg-eth0
echo "GATEWAY=${NET_GATEWAY}" >> ${MOUNTPOINT}/etc/sysconfig/network-scripts/ifcfg-eth0
echo "IPV6INIT=no" >> ${MOUNTPOINT}/etc/sysconfig/network-scripts/ifcfg-eth0

#change root password
echo "passwd change root password"
chroot ${MOUNTPOINT} passwd
#tuning system
#set the file limit
cat >> ${MOUNTPOINT}/etc/security/limits.conf << EOF
*           soft   nofile       65535
*           hard   nofile       65535
EOF

echo "disable the ipv6"
mkdir -p ${MOUNTPOINT}/etc/modprobe.d
cat > ${MOUNTPOINT}/etc/modprobe.d/ipv6.conf << EOF
install ipv6 /bin/true
EOF

cat > ${MOUNTPOINT}/etc/modprobe.d/i915-kms.conf << EOF
options i915 modeset=0
EOF

##########################vbox###############################

#yum -y install --installroot=${MOUNTPOINT} kernel-devel gcc make
#yum -y install --installroot=${MOUNTPOINT} libXinerama mesa-libGL libXcursor SDL fontconfig libSM dejavu-sans-fonts
#cp VirtualBox-4.1.12-77245-Linux_x86.run ${MOUNTPOINT}
#chroot ${MOUNTPOINT} /VirtualBox-4.1.12-77245-Linux_x86.run
#rm -f ${MOUNTPOINT}/VirtualBox-4.1.12-77245-Linux_x86.run
##########################vbox###############################

cat > ${MOUNTPOINT}/etc/locale.nopurge << EOF
MANDELETE
DONTBOTHERNEWLOCALE
SHOWFREEDSPACE
#VERBOSE
en_US
en_US.UTF-8
zh
zh_CN
zh_CN.UTF-8
EOF

cp localepurge ${MOUNTPOINT}/
chmod 755 ${MOUNTPOINT}/localepurge
chroot ${MOUNTPOINT} /localepurge
rm -f ${MOUNTPOINT}/localepurge

rm -f ${MOUNTPOINT}/usr/lib/locale/locale-archive
chroot ${MOUNTPOINT} localedef -i zh_CN -f GB2312 zh_CN
chroot ${MOUNTPOINT} localedef -i en_US -f ISO-8859-1 en_US
chroot ${MOUNTPOINT} localedef -i zh_CN -f UTF-8 zh_CN.UTF-8
chroot ${MOUNTPOINT} localedef -i en_US -f UTF-8 en_US.UTF-8

#mark my sign
cat > ${MOUNTPOINT}/johnyin.txt << EOF
my message
EOF

sed -i "s/READONLY=no/READONLY=yes/g" ${MOUNTPOINT}/etc/sysconfig/readonly-root 

sync

umount ${MOUNTPOINT}
exit 0

