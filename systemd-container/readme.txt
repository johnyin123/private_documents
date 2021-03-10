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
REPO=http://mirrors.163.com/debian
PKG+="systemd-container,ifupdown,iproute2,procps,busybox"
debootstrap --verbose --no-check-gpg --variant=minbase --include=${PKG} stable ${DIR}/${MACHINE} ${REPO}

#man systemd.nspawn
#Use host networking
cat<<EOF > /etc/systemd/nspawn/debian.nspawn
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





