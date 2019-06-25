#!/bin/bash
set -o nounset -o pipefail
DIRNAME="$(dirname "$0")"
SCRIPTNAME=${0##*/}

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi


DEBIAN_VERSION=${DEBIAN_VERSION:-stretch}
FS_TYPE=${FS_TYPE:-jfs}

if [ "$UID" -ne "0" ]
then 
	echo "Must be root to run this script." 
	exit 1
fi

prepair_disk() {
    # DISK="/dev/sdb"
    # PART_BOOT="/dev/sdb1"
    # PART_ROOT="/dev/sdb2"

    truncate -s 8G ${DIRNAME}/DISK.IMG
    DISK=$(losetup -fP --show ${DIRNAME}/DISK.IMG)
    PART_BOOT="${DISK}p1"
    PART_ROOT="${DISK}p2"

    parted -s "${DISK}" "mklabel msdos"
    parted -s "${DISK}" "mkpart primary fat32 1M 128M"
    parted -s "${DISK}" "mkpart primary ${FS_TYPE} 129M 100%"

    echo -n "Formatting BOOT partition..."
    mkfs.vfat -n "BOOT" ${PART_BOOT}
    echo "done."

    echo "Formatting ROOT partition..."
    mkfs -t ${FS_TYPE} -q -L "ROOTFS" ${PART_ROOT}
    echo "done."
    mount ${PART_ROOT} ${DIRNAME}/buildroot/
}

mkdir -p ${DIRNAME}/buildroot/

debootstrap --verbose --arch arm64 --variant=minbase --include=tzdata,locales,dialog,apt-utils --foreign ${DEBIAN_VERSION} ${DIRNAME}/buildroot http://mirrors.163.com/debian 

unset PROMPT_COMMAND
cp /usr/bin/qemu-aarch64-static ${DIRNAME}/buildroot/usr/bin/

mount --bind /dev  ${DIRNAME}/buildroot/dev
chroot ${DIRNAME}/buildroot /bin/bash <<EOSHELL
mount -t proc none /proc
mount -t sysfs none /sys

/debootstrap/debootstrap --second-stage

echo 'Acquire::http::User-Agent "debian dler";' > /etc/apt/apt.conf
echo 'APT::Install-Suggests "0";'>> /etc/apt/apt.conf

#echo "dhd" >> /etc/modules

cat > /etc/fstab << EOF
LABEL=ROOTFS	/	${FS_TYPE}	defaults,errors=remount-ro,noatime	0	1
LABEL=BOOT	/boot	vfat	ro	0	2
EOF

cat > /etc/apt/sources.list << EOF
deb http://mirrors.163.com/debian ${DEBIAN_VERSION} main non-free contrib
deb http://mirrors.163.com/debian ${DEBIAN_VERSION}-proposed-updates main non-free contrib
deb http://mirrors.163.com/debian-security ${DEBIAN_VERSION}/updates main contrib non-free
EOF
echo usb950d > /etc/hostname

apt update
apt -y upgrade

#dpkg-reconfigure locales
sed -i "s/^# *zh_CN.UTF-8/zh_CN.UTF-8/g" /etc/locale.gen
locale-gen
echo -e 'LANG="zh_CN.UTF-8"\nLANGUAGE="zh_CN:zh"\nLC_ALL="zh_CN.UTF-8"\n' > /etc/default/locale

#echo "Asia/Shanghai" > /etc/timezone
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

DEBIAN_FRONTEND=noninteractive apt -y install systemd-sysv rsyslog udev isc-dhcp-client binutils netbase console-setup ifupdown iproute openssh-server initramfs-tools jfsutils u-boot-tools fake-hwclock
apt -y install openssh-client iputils-ping wget net-tools ntpdate vim less wireless-tools wpasupplicant file blueman pulseaudio pulseaudio-module-bluetooth pavucontrol bluez-firmware mpg123 sysvinit-core 
apt -y install lightdm fonts-droid-fallback xserver-xorg xfce4 xfce4-terminal mpv smplayer qt4-qtconfig libqt4-opengl 
cat << EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF

cat << EOF > /etc/network/interfaces.d/eth0
auto eth0
allow-hotplug eth0
iface eth0 inet static
    address 192.168.168.168
    netmask 255.255.255.0
#    up (ip route add 10.0.0.0/8 via 10.32.166.1 || true)
EOF

cat << EOF > /etc/network/interfaces.d/wifi
auto wlan0
allow-hotplug wlan0
iface wlan0 inet dhcp
    wireless_mode managed
    wireless_essid any
    #wpa-driver wext
    wpa-conf /etc/wpa.conf
    up (ip r a default via 10.32.166.129||true)
EOF

cat << EOF > /etc/wpa.conf
ap_scan=1
network={
	ssid="xk-admin"
	scan_ssid=1
	#key_mgmt=wpa-psk
	psk="ADMIN@123"
}
EOF

cat << EOF > /etc/rc.local
#!/bin/sh -e
exit 0
EOF
chmod 755 /etc/rc.local

echo "enable fw_printenv command"
cat >/etc/fw_env.config <<EOF
# Device to access      offset          env size
/dev/mmcblk1            0x27400000      0x10000
EOF

systemctl enable getty@tty1
systemctl enable getty@tty2
systemctl set-default multi-user.target

mkdir -p /etc/initramfs/post-update.d/

cat>/etc/initramfs/post-update.d/99-uboot<<"EOF"
#!/bin/sh
echo "update-initramfs: Converting to u-boot format" >&2
tempname="/boot/uInitrd-$1"
mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d $2 $tempname > /dev/null
exit 0
EOF
chmod 755 /etc/initramfs/post-update.d/99-uboot

echo "修改systemd journald日志存放目录为内存，也就是/run/log目录，限制最大使用内存空间64MB"

sed -i 's/#Storage=auto/Storage=volatile/' /etc/systemd/journald.conf
sed -i 's/#RuntimeMaxUse=/RuntimeMaxUse=64M/' /etc/systemd/journald.conf

cat >/etc/profile.d/johnyin.sh<<'EOF'
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF

exit

EOSHELL

chroot ${DIRNAME}/buildroot/ /bin/bash

chroot ${DIRNAME}/buildroot/ /bin/bash <<EOSHELL
umount /proc
umount /sys
EOSHELL

umount ${DIRNAME}/buildroot/dev

final_disk() {
    umount ${DIRNAME}/buildroot/
    losetup -d ${DIRNAME}/DISK.IMG
}

gen_uEnv_ini() {
    cat > /boot/uEnv.ini <<'EOF'
dtb_name=/dtb/meson-gxl-s905d-phicomm-n1.dtb
bootargs=root=LABEL=ROOTFS rootflags=rw fsck.fix=yes fsck.repair=yes net.ifnames=0 console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 
EOF
}

gen_s905_net_boot_autoscript() {
    cat > /boot/s905_autoscript.nfs.cmd <<'EOF'
setenv kernel_addr  "0x11000000"
setenv initrd_addr  "0x13000000"
setenv dtb_mem_addr "0x1000000"
setenv serverip 192.168.168.2
setenv ipaddr 192.168.168.168
setenv bootargs "root=/dev/nfs nfsroot=${serverip}:/nfsshare/root rw net.ifnames=0 console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 rootwait"
setenv bootcmd_pxe "tftp ${kernel_addr} zImage; tftp ${initrd_addr} uInitrd; tftp ${dtb_mem_addr} dtb.img; booti ${kernel_addr} ${initrd_addr} ${dtb_mem_addr} "
run bootcmd_pxe
EOF
}

gen_s905_autoscript() {
    cat > /boot/s905_autoscript.cmd <<'EOF'
setenv env_addr     "0x10400000"
setenv kernel_addr  "0x11000000"
setenv initrd_addr  "0x13000000"
setenv dtb_mem_addr "0x1000000"
setenv boot_start booti ${kernel_addr} ${initrd_addr} ${dtb_mem_addr}
if fatload usb 0 ${kernel_addr} zImage; then if fatload usb 0 ${initrd_addr} uInitrd; then if fatload usb 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize};fi; if fatload usb 0 ${dtb_mem_addr} ${dtb_name}; then run boot_start; else store dtb read ${dtb_mem_addr}; run boot_start;fi;fi;fi;
if fatload usb 1 ${kernel_addr} zImage; then if fatload usb 1 ${initrd_addr} uInitrd; then if fatload usb 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize};fi; if fatload usb 1 ${dtb_mem_addr} ${dtb_name}; then run boot_start; else store dtb read ${dtb_mem_addr}; run boot_start;fi;fi;fi;
if fatload mmc 0 ${kernel_addr} zImage; then if fatload mmc 0 ${initrd_addr} uInitrd; then if fatload mmc 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize};fi; if fatload mmc 0 ${dtb_mem_addr} ${dtb_name}; then run boot_start; else store dtb read ${dtb_mem_addr}; run boot_start;fi;fi;fi;
EOF
}

install_bootloader() {
    gen_uEnv_ini
    gen_s905_autoscript
    mkimage -C none -A arm -T script -d s905_autoscript.cmd s905_autoscript
    mkimage -C none -A arm -T script -d s905_autoscript.nfs.cmd s905_autoscript.nfs
    mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d initramfs-linux.img uInitrd
}

