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

VERSION+=("e28c813[2023-12-26T14:29:30+08:00]:os_centos_init.sh")
# /etc/yum.conf
# [main]
# proxy=http://srv:port
# proxy_username=u
# proxy_password=p
# sslverify=false
# PASSWORD: root password
# NAME_SERVER: dns server
# HOSTNAME: target hostname
# RELEASE_VER: 7.9.2009/7/8/9 special target system version detail
centos_build() {
    local root_dir=$1
    local cache_dir="${2}"
    local include_pkg="${3}"
    local REPO=${root_dir}/etc/yum.repos.d/local.repo
    local HOST_YUM=$(command -v yum || command -v dnf || { echo 'yum/dnf no found!'; return 1; })
    case "${INST_ARCH:-}" in
        aarch64)
            HOST_YUM+=" --forcearch=aarch64"
            echo "use aarch64"
            [ -e "/usr/bin/qemu-aarch64-static" ] || { echo "Need: apt install qemu-user-static"; return 1; }
            mkdir -p ${root_dir}/usr/bin/ && cp /usr/bin/qemu-aarch64-static ${root_dir}/usr/bin/
            ;;
        *)  echo "use host ARCH";;
    esac
    HOST_YUM+=" ${RELEASE_VER:+--releasever=${RELEASE_VER}} --installroot=${root_dir}"
    mkdir -p ${root_dir}/etc/yum.repos.d/ ${cache_dir}
    [ -r ${REPO} ] || {
        # yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        cat>> ${REPO} <<'EOF'
# centos7 : baseurl=http://mirrors.aliyun.com/centos/$releasever/os/$basearch/
# centos8 : baseurl=http://mirrors.aliyun.com/centos-vault/releasever/BaseOS/$basearch/os/
# rocky   : baseurl=https://mirrors.aliyun.com/rockylinux/$releasever/BaseOS/$basearch/os/
# baseurl=http://192.168.168.1/BaseOS
# baseurl=http://192.168.168.1/minimal
[mybase]
name=CentOS Family-$releasever - Base
gpgcheck=0
EOF
    ${EDITOR:-vi} ${REPO} || true
    }
    ${HOST_YUM} --installroot=${root_dir} -y install yum passwd
    rm -rf ${root_dir}/root/.rpmdb
    echo ${HOSTNAME:-cent-tpl} > ${root_dir}/etc/hostname
    echo "nameserver ${NAME_SERVER:-114.114.114.114}" > ${root_dir}/etc/resolv.conf
    rm -f ${root_dir}/etc/localtime || true
    for mp in /dev /sys /proc
    do
        mount -o bind ${mp} ${root_dir}${mp} || true
    done
    echo "start install group core"
    LC_ALL=C LANGUAGE=C LANG=C chroot "${root_dir}" /bin/bash -x <<EOSHELL
    yum -y --disablerepo=* --enablerepo=mybase group install --exclude kernel-tools --exclude iw*-firmware core || true
    echo "start install packages: ${include_pkg}"
    yum -y --disablerepo=* --enablerepo=mybase update || true
    for p in ${include_pkg}; do
        yum -y --disablerepo=* --enablerepo=mybase install \${p} || true
    done
    systemd-firstboot --root=/ --locale=zh_CN.UTF-8 --locale-messages=zh_CN.UTF-8 --timezone="Asia/Shanghai" --hostname="localhost" --setup-machine-id || true
    # timedatectl set-timezone Asia/Shanghai
    rm -f /etc/localtime && ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    # localectl
    echo "${PASSWORD:-password}" | passwd --stdin root || true
    systemctl enable getty@tty0 || true
    sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config || true
EOSHELL
    for mp in /dev /sys /proc
    do
        umount -R -v ${root_dir}${mp} || true
    done
    rm -rf ${REPO} || true
    return 0
}
centos_build2() {
    local root_dir=$1
    local cache_dir="${2}"
    local include_pkg="${3}"
    local REPO=${root_dir}/local.repo
    local HOST_YUM=$(command -v yum || command -v dnf || { echo 'yum/dnf no found!'; return 1; })
    case "${INST_ARCH:-}" in
        aarch64)
            HOST_YUM+=" --forcearch=aarch64"
            echo "use aarch64"
            [ -e "/usr/bin/qemu-aarch64-static" ] || { echo "Need: apt install qemu-user-static"; return 1; }
            mkdir -p ${root_dir}/usr/bin/ && cp /usr/bin/qemu-aarch64-static ${root_dir}/usr/bin/
            ;;
        *)  echo "use host ARCH";;
    esac
    HOST_YUM+=" ${RELEASE_VER:+--releasever=${RELEASE_VER}} -c ${REPO} --installroot=${root_dir} --downloadonly --destdir=${cache_dir}"
    [ -d "${root_dir}" ] || mkdir -p ${root_dir}
    [ -d "${cache_dir}" ] || mkdir -p ${cache_dir}
    [ -r ${REPO} ] || {
        # yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        cat>> ${REPO} <<'EOF'
# centos7 : baseurl=http://mirrors.aliyun.com/centos/$releasever/os/$basearch/
# centos8 : baseurl=http://mirrors.aliyun.com/centos-vault/releasever/BaseOS/$basearch/os/
# rocky   : baseurl=https://mirrors.aliyun.com/rockylinux/$releasever/BaseOS/$basearch/os/
# baseurl=http://192.168.168.1/BaseOS
# baseurl=http://192.168.168.1/minimal
[mybase]
name=CentOS Family-$releasever - Base
gpgcheck=0
EOF
    ${EDITOR:-vi} ${REPO} || true
    }
    rpm --root=${root_dir} --dbpath=/var/lib/rpm --initdb
    # ${HOST_YUM} -y install yum passwd ${include_pkg}
    # rpm --root=${root_dir} --dbpath=/var/lib/rpm --import ${root_dir}/etc/pki/rpm-gpg/RPM-GPG-KEY-*
    echo "start install group core"
    # ${HOST_YUM} -y group install core
    ${HOST_YUM} -y group install --exclude kernel-tools --exclude iw*-firmware core
    rpm --root=${root_dir} --dbpath=/var/lib/rpm --ignorearch --nodigest --nosignature -ivh ${cache_dir}/*.rpm
    echo ${HOSTNAME:-cent-tpl} > ${root_dir}/etc/hostname
    echo "nameserver ${NAME_SERVER:-114.114.114.114}" > ${root_dir}/etc/resolv.conf
    # rpm -qi centos-release
    rm -f ${root_dir}/etc/localtime || true
    for mp in /dev /sys /proc
    do
        mount -o bind ${mp} ${root_dir}${mp} || true
    done
    LC_ALL=C LANGUAGE=C LANG=C chroot "${root_dir}" /bin/bash -x <<EOSHELL
    echo "backup repo, enable local.repo"
    mv /etc/yum.repos.d/* /root/ || true
    mv /local.repo /etc/yum.repos.d/
    echo "fix rpm db"
    rpmdb --rebuilddb || true
    echo "start install packages: ${include_pkg}"
    yum -y update && yum -y install ${include_pkg}
    mv /etc/yum.repos.d/local.repo / || true
    mv /root/*.repo /etc/yum.repos.d/ || true
    systemd-firstboot --root=/ --locale=zh_CN.UTF-8 --locale-messages=zh_CN.UTF-8 --timezone="Asia/Shanghai" --hostname="localhost" --setup-machine-id || true
    # timedatectl set-timezone Asia/Shanghai
    echo "${PASSWORD:-password}" | passwd --stdin root || true
    systemctl enable getty@tty0 || true
    sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config || true
EOSHELL
    for mp in /dev /sys /proc
    do
        umount -R -v ${root_dir}${mp} || true
    done
    rm -rf ${REPO} || true
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
export readonly HISTCONTROL=ignoredups:erasedups
export readonly HISTSIZE=100000
export readonly HISTFILESIZE=100000
shopt -s histappend
EOF

    cat >/etc/profile.d/johnyin.sh<<"EOF"
# Not bash
[ -n "${BASH_VERSION:-}" ] || return 0
# Not an interactive shell?
[[ $- == *i* ]] || return 0

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
    cat /etc/sysctl.conf 2>/dev/null > /etc/sysctl.conf.bak || true
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
    cat << EOF > /etc/sysctl.d/90-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    cat << EOF > /etc/sysctl.d/90-perf.conf
kernel.sched_autogroup_enabled = 0
vm.min_free_kbytes = 131072
sysctl vm.dirty_ratio = 60
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
    rpm -q openssh-server || yum -y --setopt=tsflags='nodocs' --setopt=override_install_langs=en_US.utf8 install openssh-server || true
    sed --quiet -i.orig -E \
        -e '/^\s*(UseDNS|MaxAuthTries|GSSAPIAuthentication|Port|Ciphers|MACs|PermitRootLogin|TrustedUserCAKeys).*/!p' \
        -e '$aUseDNS no' \
        -e '$aMaxAuthTries 3' \
        -e '$aGSSAPIAuthentication no' \
        -e '$aPort 60022' \
        -e '$aCiphers aes256-ctr,aes192-ctr,aes128-ctr' \
        -e '$aMACs hmac-sha1' \
        -e '$aPermitRootLogin without-password' \
        -e '$aTrustedUserCAKeys /etc/ssh/myca.pub' \
        /etc/ssh/sshd_config
    cat <<EOF >/etc/ssh/myca.pub
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
    chmod 0644 /etc/ssh/myca.pub
    # root login only prikey "PermitRootLogin without-password"
    cat <<"EOF" > /etc/ssh/sshrc
logger -i -t ssh "$(date '+%Y%m%d%H%M%S') $USER $SSH_CONNECTION"
EOF
    [ ! -d /root/.ssh ] && mkdir -m0700 /root/.ssh
    cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
    chmod 0600 /root/.ssh/authorized_keys
    # ssh tap device no create, when ControlMaster !!!!
    cat <<EOF >/root/.ssh/config
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
Host github.com
    Port=22
Host *
    Port=60022
#    ControlMaster auto
#    ControlPath  ~/.ssh/sockets/%r@%h-%p
#    ControlPersist 600
EOF
    mkdir -p /root/.ssh/sockets/
    chmod 0600 /root/.ssh/config

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
#     cat > /etc/modprobe.d/ipv6.conf << EOF
# install ipv6 /bin/true
# EOF
    echo "centos_disable_ipv6 no used!!!"
}
export -f centos_disable_ipv6

centos_service_init() {
    systemctl set-default multi-user.target
    local netsvc=network
    systemctl status NetworkManager.service >/dev/null 2>&1 && {
        sed -i "/NM_CONTROLLED=/d" /etc/sysconfig/network-scripts/ifcfg-eth0
        netsvc="NetworkManager.service dbus-broker.service haveged.service"
    }
    {
        chkconfig 2>/dev/null | egrep -v "crond|sshd|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}'
        systemctl list-unit-files -t service  | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}'
        for _s in ${netsvc}; do echo "systemctl enable $_s"; done
        systemctl list-unit-files -t timer  | grep enabled | egrep -v "logrotate.timer|sysstat-collect.timer|sysstat-summary.timer" | awk '{print "systemctl disable", $1}' | awk '{print "systemctl disable", $1}'
    } | bash -x || true
    #systemctl list-unit-files -t service | awk '$2 == "enabled" {printf "systemctl disable %s\n", $1}'
}
export -f centos_service_init

centos_zramswap_init() {
    local size_mb=$1
    cat<<EOF > /etc/default/zramswap
ZRAM_DEV=/dev/zram0
# Compression algorithm selection
# speed: lz4 > zstd > lzo compression: zstd > lzo > lz4
ALGO=lzo

# Specifies a static amount of RAM in MiB
SIZE=${size_mb}MiB

# Specifies the priority for the swap devices, see swapon(2)
# This should probably be higher than hdd/ssd swaps.
#PRIORITY=100
EOF
    cat<<'EOF' >/lib/systemd/system/zramswap.service
[Unit]
Description=Linux zramswap setup
[Service]
Environment=ALGO=lzo
Environment=SIZE=256MiB
Environment=ZRAM_DEV=/dev/zram0
Environment=PRIORITY=100
EnvironmentFile=-/etc/default/zramswap
ExecStartPre=-/sbin/modprobe zram
ExecStart=/sbin/zramctl ${ZRAM_DEV}
ExecStart=/sbin/zramctl -a "${ALGO}" -s "${SIZE}" ${ZRAM_DEV}
ExecStart=/sbin/mkswap ${ZRAM_DEV}
ExecStart=/sbin/swapon -p "${PRIORITY}" ${ZRAM_DEV}
ExecStop=/sbin/swapoff ${ZRAM_DEV}
ExecStop=/sbin/zramctl -r ${ZRAM_DEV}
Type=oneshot
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
EOF
}

centos_zramswap_init1() {
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

centos_versionlock () {
    local pkg=${1}
    yum -y -q list installed yum-versionlock || yum -y install yum-versionlock
    yum versionlock add ${pkg}
    #yum versionlock list httpd
}
export -f centos_versionlock

centos_minimum_init() {
    yum clean all
    rm -rf /var/cache/yum
    rm -rf /var/tmp/yum-*
}
export -f centos_minimum_init
