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

VERSION+=("os_centos_init.sh - 71e15f2 - 2021-04-01T10:37:58+08:00")
centos_limits_init() {
    #set the file limit
    cat > /etc/security/limits.d/tun.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
}
export -f centos_limits_init

centos_sysctl_init() {
    mv /etc/sysctl.conf /etc/sysctl.conf.bak
    cat << EOF > /etc/sysctl.conf
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
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
    sed -i 's/#UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
    sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' /etc/ssh/sshd_config
    sed -i 's/#Port.*/Port 60022/g' /etc/ssh/sshd_config
    sed -i 's/GSSAPIAuthentication.*/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
    (grep -v -E "^Ciphers|^MACs|^PermitRootLogin" /etc/ssh/sshd_config ; echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr"; echo "MACs    hmac-sha1"; echo "PermitRootLogin without-password";) | tee /etc/ssh/sshd_config.bak
    mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    # root login only prikey "PermitRootLogin without-password"

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
    chkconfig 2>/dev/null | egrep -v "crond|sshd|network|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}' | bash
    systemctl list-unit-files | grep service | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}' | bash
}
export -f centos_service_init

centos_zswap_init() {
    local size_mb=$(($1*1024*1024))
    ( grep -v -E "^/dev/zram0" /etc/fstab ; echo "/dev/zram0   none swap sw,pri=32767 0 0"; ) | tee /etc/fstab.bak
    mv /etc/fstab.bak /etc/fstab
    cat <<EOF > /etc/udev/rules.d/99-zswap.rules
KERNEL=="zram0", ACTION=="add", ATTR{disksize}="${size_mb}", RUN="/sbin/mkswap /\$root/\$name"
EOF
    echo "zram" > /etc/modules-load.d/zram.conf 
}
export -f centos_zswap_init

