https://wiki.archlinux.org/index.php/Systemd-nspawn

machinectl --verify=no --host=root@host:port pull-tar http://http_srv/new.tar.gz new

$ apt-get install systemd-container
$ echo 'kernel.unprivileged_userns_clone=1' >/etc/sysctl.d/nspawn.conf
$ systemctl restart systemd-sysctl.service
# guest OS should also have the systemd-container package installed. 

# cd /var/lib/machines
# debootstrap --include=systemd-container --components=main,universe <codename> ${NAME} <repository-url>


DIR=/var/lib/machines
MACHINE=debian

# systemd-nspawn support raw image format, with parititon or not.
# DISK_FILE=<you file image>
# truncate -s 2G ${DISK_FILE}
# # docker img can without partitions info. parted is not must need!!
# parted -s ${DISK_FILE} -- mklabel msdos \
# 	    mkpart primary xfs 2048s -1s \
# 	    set 1 boot on
# DEV=$(losetup -f --show "${DISK_FILE}" --offset=$((2048 * 512)))
# mkfs.ext4 "$DEV" -q >/dev/null
# mount -o offset=$((2048*512)) "${DISK_FILE}" ${DIR}/${MACHINE}

REPO=http://mirrors.163.com/debian
PKG+="systemd-container,ifupdown,iproute2,procps,busybox"
debootstrap --verbose --no-check-gpg --variant=minbase --include=${PKG} stable ${DIR}/${MACHINE} ${REPO}

#man systemd.nspawn
#Use host networking
# /etc/systemd/nspawn/${MACHINE}.nspawn
# /run/systemd/nspawn/${MACHINE}.nspawn
# /var/lib/machines/${MACHINE}.nspawn
cat<<EOF > /etc/systemd/nspawn/${MACHINE}.nspawn
[Exec]
Boot=on

[Network]
VirtualEthernet=yes
Bridge=br-ext
EOF

cat<<EOF > ${DIR}/${MACHINE}/etc/network/interfaces.d/host0
auto host0
allow-hotplug host0
iface host0 inet static
    address 10.32.166.32/25
    gateway 10.32.166.1
EOF

# cat > ${DIR}/${MACHINE}/etc/systemd/network/host0.network <<EOF
# [Match]
# Name=host0
# [Network]
# #Address=10.32.166.32/25
# #Gateway=10.32.166.1
# DHCP=ipv4
# Domains=$DOMAIN
# EOF
# 
# systemctl -q -M "$MACHINE" enable systemd-networkd --now
# systemctl -q -M "$MACHINE" enable systemd-resolved --now
# systemctl -q -M "$MACHINE" enable ssh --now

systemctl set-property systemd-nspawn@${MACHINE}.service MemoryMax=2G
systemctl set-property systemd-nspawn@${MACHINE}.service CPUQuota=200%

# This will create permanent files in /etc/systemd/system.control/systemd-nspawn@${MACHINE}.service.d/

# Enable container to start at boot
$ machinectl enable container-name / systemctl enable systemd-nspawn@container-name.service

$ systemd-nspawn -D ${DIR}/${MACHINE} -U --machine test
root@debian:~# passwd
#root@debian:~# echo 'pts/1' >> /etc/securetty  # allow login via local tty
root@debian:~# apt clean
root@debian:~# logout

# X11 
systemd-nspawn -E DISPLAY="$DISPLAY" ...
# audio
$ systemd-nspawn -E PULSE_SERVER="unix:/pulse-guest.socket" --bind=/pulse-host.socket:/pulse-guest.socket ...

systemd-nspawn -D "$DEST" \
    --bind=/tmp/.X11-unix \
    --bind=/run/user/1000/pulse \
    --bind=/dev/snd \
    --bind=/dev/video0 \
    --bind=/etc/machine-id \
    --bind=/dev/shm \
    --share-system sudo \
    -u skype \
    env DISPLAY=:0 PULSE_SERVER=unix:/run/user/1000/pulse/native skype

# boot into the container
systemd-nspawn -b -D ~/MyContainer

machinectl start/shell/enable .... 

$ journalctl -M container-name
Show control group contents:

$ systemd-cgls -M container-name
See startup time of container:

$ systemd-analyze -M container-name
For an overview of resource usage:

$ systemd-cgtop


# ra2/AOE2
dpkg --add-architecture i386 && apt update  && apt install wine wine32 libgl1:i386 libgl1-mesa-dri:i386 libpulse0:i386

systemd-nspawn -D "${DIRNAME}/game" useradd -s /bin/bash -m johnyin

#    --setenv=DISPLAY=${DISPLAY}
systemd-nspawn -D "${DIRNAME}/game" \
        --bind-ro=/tmp/.X11-unix \
        --bind-ro=/home/johnyin/.Xauthority:/home/johnyin/.Xauthority \
        --network-veth \
        --network-bridge=br-ext \
        --bind-ro=/home/johnyin/.config/pulse/cookie \
        --bind-ro=/run/user/1000/pulse:/run/user/host/pulse \
        -u johnyin env DISPLAY=:0 PULSE_SERVER=unix:/run/user/host/pulse/native wine /home/johnyin/ra2/ra2.exe
        #--boot <winecfg/useradd......>
        #--private-users=0 --private-users-chown --bind=/share_rw:/share/

# cat<<EOF > /etc/systemd/nspawn/${MACHINE}.nspawn
# [Exec]
# Boot=on
# PrivateUsers=0
#
# [Network]
# VirtualEthernet=yes
# Bridge=br-ext
#
# [Files]
# PrivateUsersChown=yes
# Bind=/home/johnyin/:/home/johnyin/disk/
#
# BindReadOnly=/tmp/.X11-unix
# BindReadOnly=/home/johnyin/.Xauthority:/home/johnyin/.Xauthority
# BindReadOnly=/home/johnyin/.config/pulse/cookie
# BindReadOnly=/run/user/1000/pulse:/run/user/host/pulse
#
# EOF
# systemd-run -M game --uid=johnyin -E DISPLAY=:0 -E PULSE_SERVER=unix:/run/user/host/pulse/native /bin/google-chrome

