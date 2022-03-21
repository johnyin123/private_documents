#!/bin/echo Warnning, this library must only be sourced!
# shellcheck disable=SC2086 disable=SC2155

# TO BE SOURCED ONLY ONCE:
if [ -z ${__centos__inc+x} ]; then
    __centos__inc=1
else
    return 0
fi
# Disable unicode.
LC_ALL=C
LANG=C

#set -o pipefail  # trace ERR through pipes,only available on Bash
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

VERSION+=("093ddbd[2022-03-18T13:18:10+08:00]:os_centos_init.sh")
centos_build() {
    local root_dir=$1
    local REPO=$(mktemp -d)/local.repo
    local YUM_OPT="--disablerepo=* --enablerepo=centos -q --noplugins --nogpgcheck --config=${REPO}" #--setopt=tsflags=nodocs"
    [ -r ${REPO} ] || {
        # yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        cat> ${REPO} <<'EOF'
[centos]
name=centos
# baseurl=http://mirrors.163.com/centos/7.7.1908/os/x86_64/
baseurl=http://10.0.2.1:8080/
gpgcheck=0
EOF
    ${EDITOR:-vi} ${REPO} || true
}
# $ mkdir -p $centos_root
# # initialize rpm database
# $ rpm --root $centos_root --initdb
# # download and install the centos-release package, it contains our repository sources
# $ yumdownloader --destdir=. centos-release
# # $ yum reinstall --downloadonly --downloaddir . centos-release
# $ rpm --root $centos_root -ivh --nodeps centos-release*.rpm
# $ rpm --root $centos_root --import  $centos_root/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
# # install yum without docs and install only the english language files during the process
# $ yum -y --installroot=$centos_root --setopt=tsflags='nodocs' --setopt=override_install_langs=en_US.utf8 install yum
# # configure yum to avoid installing of docs and other language files than english generally
# $ sed -i "/distroverpkg=centos-release/a override_install_langs=en_US.utf8\ntsflags=nodocs" $centos_root/etc/yum.conf
# # chroot to the environment and install some additional tools
# $ cp /etc/resolv.conf $centos_root/etc
# # mount the device tree, as its required by some programms
# $ mount -o bind /dev $centos_root/dev
# $ chroot $centos_root /bin/bash <<EOF
# yum install -y procps-ng iputils initscripts openssh-server rsync openssh-clients passwd
# yum clean all
# $ rm -f $centos_root/etc/resolv.conf
# $ umount $centos_root/dev
#     yum ${YUM_OPT} -y --installroot=${root_dir} remove -C --setopt="clean_requirements_on_remove=1" \
# 	    firewalld \
# 	    NetworkManager \
# 	    NetworkManager-team \
# 	    NetworkManager-tui \
# 	    NetworkManager-wifi \
#       linux-firmware* \
# 	    aic94xx-firmware \
# 	    alsa-firmware \
# 	    ivtv-firmware \
# 	    iwl100-firmware \
# 	    iwl1000-firmware \
# 	    iwl105-firmware \
# 	    iwl135-firmware \
# 	    iwl2000-firmware \
# 	    iwl2030-firmware \
# 	    iwl3160-firmware \
# 	    iwl3945-firmware \
# 	    iwl4965-firmware \
# 	    iwl5000-firmware \
# 	    iwl5150-firmware \
# 	    iwl6000-firmware \
# 	    iwl6000g2a-firmware \
# 	    iwl6000g2b-firmware \
# 	    iwl6050-firmware \
# 	    iwl7260-firmware \
# 	    iwl7265-firmware
    cat > ${root_dir}/etc/default/grub <<'EOF'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
EOF
    cat > ${root_dir}/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "cn"
EndSection
EOF
    echo 'KEYMAP="cn"' > ${root_dir}/etc/vconsole.conf


    chmod 755 ${root_dir}/etc/rc.d/rc.local
    rm -f ${root_dir}/ssh/ssh_host_*
    LC_ALL=C LANGUAGE=C LANG=C chroot ${root_dir} /bin/bash <<EOSHELL
    rm -f /etc/locale.conf /etc/localtime /etc/hostname /etc/machine-id /etc/.pwd.lock
    systemd-firstboot --root=/ --locale=zh_CN.UTF-8 --locale-messages=zh_CN.UTF-8 --timezone="Asia/Shanghai" --hostname="localhost" --setup-machine-id
    #localectl set-locale LANG=zh_CN.UTF-8
    #localectl set-keymap cn
    #localectl set-x11-keymap cn
    echo "${PASSWORD:-password}" | passwd --stdin root
    systemctl enable getty@tty1

    centos_limits_init
    centos_disable_selinux
    centos_sshd_init
    centos_disable_ipv6
    centos_service_init
    centos_sysctl_init
    centos_zramswap_init 512
EOSHELL
    return 0
}

centos_limits_init() {
    #set the file limit
    cat > /etc/security/limits.d/tun.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
    cat <<EOF > /etc/profile.d/os-security.sh
export readonly TMOUT=900
export readonly HISTFILE
export readonly HISTCONTROL=erasedups
EOF

    cat >/etc/profile.d/johnyin.sh<<"EOF"
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF
# security set
sed -i "s/^PASS_MAX_DAYS.*$/PASS_MAX_DAYS 90/g" /etc/login.defs
sed -i "s/^PASS_MIN_DAYS.*$/PASS_MIN_DAYS 2/g" /etc/login.defs
sed -i "s/^PASS_MIN_LEN.*$/PASS_MIN_LEN 8/g" /etc/login.defs
sed -i "s/^PASS_WARN_AGE.*$/PASS_WARN_AGE 7/g" /etc/login.defs
sed -i "1 a auth       required     pam_tally2.so onerr=fail  deny=6  unlock_time=1800" /etc/pam.d/sshd
sed -i "/password/ipassword    required      pam_cracklib.so lcredit=-1 ucredit=-1 dcredit=-1 ocredit=-1" /etc/pam.d/system-auth
}
export -f centos_limits_init

centos_sysctl_init() {
    mv /etc/sysctl.conf /etc/sysctl.conf.bak
    cat << EOF > /etc/sysctl.conf
fs.file-max = 1000000
net.ipv4.ping_group_range = 0	2147483647
net.core.rmem_max = 134217728 
net.core.wmem_max = 134217728 
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535
net.core.wmem_default = 16777216
net.ipv4.ip_local_port_range = 1024 65531
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syncookies = 0
net.ipv4.tcp_timestamps = 0
#net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_tw_reuse = 0
#net.ipv4.ip_forward = 1
EOF
}
export -f centos_sysctl_init

centos_sshd_regenkey() {
  # Remove ssh host keys
  rm -f /etc/ssh/ssh_host_*
  systemctl stop sshd

  # Regenerate ssh host keys
  ssh-keygen -q -t rsa -N "" -f /etc/ssh/ssh_host_rsa_key
  ssh-keygen -q -t dsa -N "" -f /etc/ssh/ssh_host_dsa_key
  ssh-keygen -q -t ecdsa -N "" -f /etc/ssh/ssh_host_ecdsa_key
  ssh-keygen -q -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
  systemctl start sshd
}
export -f centos_sshd_regenkey

centos_sshd_init() {
    cp -n /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
    sed -i 's/#UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
    sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' /etc/ssh/sshd_config
    #sed -i 's/#Port.*/Port 60022/g' /etc/ssh/sshd_config
    sed -E -i "s/(Port|#\sPort|#Port)\s.{1,5}$/Port 60022/g" /etc/ssh/sshd_config
    sed -i 's/GSSAPIAuthentication.*/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
    (grep -v -E "^Ciphers|^MACs|^PermitRootLogin" /etc/ssh/sshd_config ; echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr"; echo "MACs    hmac-sha1"; echo "PermitRootLogin without-password";) | tee /etc/ssh/sshd_config.bak
    mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    # root login only prikey "PermitRootLogin without-password"
    cat <<"EOF" > /etc/ssh/sshrc
logger -i -t ssh "$(date '+%Y%m%d%H%M%S') $USER $SSH_CONNECTION"
EOF
    [ ! -d /root/.ssh ] && mkdir -m0700 /root/.ssh
    cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
    chmod 0600 /root/.ssh/authorized_keys
}
export -f centos_sshd_init

centos_chpasswd() {
    local user=$1
    local password=$2
    echo "${password}" | passwd --stdin ${user}
    # Force Users To Change Their Passwords Upon First Login
    # chage -d 0 ${user}
}
export -f centos_chpasswd

centos_disable_selinux() {
    sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
}
export -f centos_disable_selinux

centos_disable_ipv6() {
    cat > /etc/modprobe.d/ipv6.conf << EOF
install ipv6 /bin/true
EOF
}
export -f centos_disable_ipv6

centos_service_init() {
    systemctl set-default multi-user.target
    local netsvc=network
    [[ -r /etc/os-release ]] && source /etc/os-release
    VERSION_ID=${VERSION_ID:-}
    [ "${VERSION_ID#8*}" != "${VERSION_ID}" ] && {
        sed -i "/NM_CONTROLLED=/d" /etc/sysconfig/network-scripts/ifcfg-eth0
        netsvc=NetworkManager.service
    }
    {
        chkconfig 2>/dev/null | egrep -v "crond|sshd|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}'
        systemctl list-unit-files -t service  | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}'
        echo "systemctl enable ${netsvc}"
    } | bash -x
    #systemctl list-unit-files -t service | awk '$2 == "enabled" {printf "systemctl disable %s\n", $1}'
}
export -f centos_service_init

centos_zramswap_init() {
    local size_mb=$1
    cat<<EOF > /etc/default/zramswap
# Compression algorithm selection
# speed: lz4 > zstd > lzo compression: zstd > lzo > lz4
ALGO=lzo

# Specifies the amount of RAM that should be used for zram
#PERCENT=50

# Specifies a static amount of RAM in MiB
SIZE=${size_mb}

# Specifies the priority for the swap devices, see swapon(2)
# This should probably be higher than hdd/ssd swaps.
#PRIORITY=100
EOF
    cat<<EOF >/lib/systemd/system/zramswap.service
[Unit]
Description=Linux zramswap setup
[Service]
EnvironmentFile=-/etc/default/zramswap
ExecStart=/usr/sbin/zramswap start
ExecStop=/usr/sbin/zramswap stop
ExecReload=/usr/sbin/zramswap restart
Type=oneshot
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
EOF
    cat<<'EOSH' >/usr/sbin/zramswap
#!/bin/bash
readonly CONFIG="/etc/default/zramswap"
readonly SWAP_DEV="/dev/zram0"

if command -v logger >/dev/null; then
    function elog {
        logger -s "Error: $*"
        exit 1
    }
    function wlog {
        logger -s "$*"
    }
else
    function elog {
        echo "Error: $*"
        exit 1
    }
    function wlog {
        echo "$*"
    }
fi

function start {
    wlog "Starting Zram"

    # Load config
    test -r "${CONFIG}" || wlog "Cannot read config from ${CONFIG} continuing with defaults."
    source "${CONFIG}" 2>/dev/null

    # Set defaults if not specified
    : "${ALGO:=lz4}" "${SIZE:=256}" "${PRIORITY:=100}"

    SIZE=$((SIZE * 1024 * 1024)) # convert amount from MiB to bytes

    # Prefer percent if it is set
    if [ -n "${PERCENT}" ]; then
        readonly TOTAL_MEMORY=$(awk '/MemTotal/{print $2}' /proc/meminfo) # in KiB
        readonly SIZE="$((TOTAL_MEMORY * 1024 * PERCENT / 100))"
    fi

    modprobe zram || elog "inserting the zram kernel module"
    echo -n "${ALGO}" > /sys/block/zram0/comp_algorithm || elog "setting compression algo to ${ALGO}"
    echo -n "${SIZE}" > /sys/block/zram0/disksize || elog "setting zram device size to ${SIZE}"
    mkswap "${SWAP_DEV}" || elog "initialising swap device"
    swapon -p "${PRIORITY}" "${SWAP_DEV}" || elog "enabling swap device"
}

function status {
    test -x "$(which zramctl)" || elog "install zramctl for this feature"
    test -b "${SWAP_DEV}" || elog "${SWAP_DEV} doesn't exist"
    # old zramctl doesn't have --output-all
    #zramctl --output-all
    zramctl "${SWAP_DEV}"
}

function stop {
    wlog "Stopping Zram"
    test -b "${SWAP_DEV}" || wlog "${SWAP_DEV} doesn't exist"
    swapoff "${SWAP_DEV}" 2>/dev/null || wlog "disabling swap device: ${SWAP_DEV}"
    modprobe -r zram || elog "removing zram module from kernel"
}

function usage {
    cat << EOF
Usage:
    zramswap (start|stop|restart|status)
EOF
}

case "$1" in
    start)      start;;
    stop)       stop;;
    restart)    stop && start;;
    status)     status;;
    "")         usage;;
    *)          elog "Unknown option $1";;
esac
EOSH
    chmod 755 /usr/sbin/zramswap
    systemctl enable zramswap.service
}
export -f centos_zramswap_init

centos_zramswap_init2() {
    local size_mb=$(($1*1024*1024))
    ( grep -v -E "^/dev/zram0" /etc/fstab ; echo "/dev/zram0   none swap sw,pri=32767 0 0"; ) | tee /etc/fstab.bak
    mv /etc/fstab.bak /etc/fstab
    cat /usr/lib/udev/rules.d/95-late.rules >> /usr/lib/udev/rules.d/95-late.rules.bak || true
    cat <<EOF > /usr/lib/udev/rules.d/95-late.rules
KERNEL=="zram0", ACTION=="add", ATTR{disksize}="${size_mb}", RUN="/sbin/mkswap /\$root/\$name"
EOF
    echo "zram" > /etc/modules-load.d/zram.conf 
    dracut -fv
}
export -f centos_zramswap_init2

