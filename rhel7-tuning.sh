#/bin/bash

#set the file limit
cat > /etc/security/limits.d/tun.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF

# echo "disable the ipv6"
# cat > /etc/modprobe.d/ipv6.conf << EOF
# install ipv6 /bin/true
# EOF

#disable selinux
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
 
#set sshd
sed -i 's/#UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/#Port.*/Port 60022/' /etc/ssh/sshd_config
sed -i 's/GSSAPIAuthentication.*/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' /etc/ssh/sshd_config
echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
echo "MACs    hmac-sha1" >> /etc/ssh/sshd_config

service sshd restart

#tune kernel parametres
cat >> /etc/sysctl.conf << EOF
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
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_tw_reuse = 0
EOF
/sbin/sysctl -p

[ -r "motd.sh" ] && {
    cat motd.sh >/etc/motd.sh
    touch /etc/logo.txt
    chmod 644 /etc/motd.sh
    cat >> /etc/profile << EOF
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$"
export readonly PROMPT_COMMAND='{ msg=\$(history 1 | { read x y; echo \$y; });user=\$(whoami); echo \$(date "+%Y-%m-%d%H:%M:%S"):\$user:`pwd`/:\$msg ---- \$(who am i); } >> \$HOME/.history'
set -o vi
sh /etc/motd.sh
EOF
}

### Add SSH public key
if [ ! -d /root/.ssh ]; then
    mkdir -m0700 /root/.ssh
fi
cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
chmod 0600 /root/.ssh/authorized_keys

systemctl set-default multi-user.target
systemctl enable getty@tty1

netsvc=network
[[ -r /etc/os-release ]] && source /etc/os-release
[[ ${VERSION_ID:-} = 8 ]] && netsvc=NetworkManager

chkconfig 2>/dev/null | egrep -v "crond|sshd|${netsvc}|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}' | bash
systemctl list-unit-files | grep enabled | egrep -v "${netsvc}|getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}' | bash

#define the backspace button can erase the last character typed
#echo 'stty erase ^H' >> /etc/profile

#I/O scheduler算法
# echo deadline > /sys/block/sda/queue/scheduler
# echo 500 > /sys/block/sda/queue/iosched/read_expire
# echo 1000 > /sys/block/sda/queue/iosched/write_expire
# #预读扇区数
# blockdev --setra 4096 /dev/sda

cat << EOF
RHEL init tunning script 4 src@neusoft
yin.zh@neusoft.com
Recommond to restart this server 
EOF

exit 0


#                 cat  /etc/sysconfig/modules/aoe.modules 
#                 #!/bin/sh
#                 /sbin/modprobe aoe



# chkconfig --list | awk '{print "chkconfig " $1 " off"}' > /tmp/chkconfiglist.sh;/bin/sh /tmp/chkconfiglist.sh;rm -rf /tmp/chkconfiglist.sh 
# chkconfig  crond on 
# chkconfig  network on 
# chkconfig  sshd on 
# chkconfig  syslog on 
# echo 'PS1="\[\e[37;40m\][\[\e[32;40m\]\u\[\e[37;40m\]@\h \[\e[35;40m\]\W\[\e[0m\]]\\$ \[\e[33;40m\]"' >> /etc/profile 
# #修改shell命令的history记录个数 
# sed -i 's/HISTSIZE=.*$/HISTSIZE=100/g' /etc/profile 
# source /etc/profile 
# #记录每个命令 
# mkdir /root/logs 
# echo "export PROMPT_COMMAND='{ msg=\$(history 1 | { read x y; echo \$y; });user=\$(whoami); echo \$(date \"+%Y-%m-%d %H:%M:%S\"):\$user:\`pwd\`/:\$msg ---- \$(who am i); } >> \$HOME/logs/\`hostname\`.\`whoami\`.history-timestamp'" >> /root/.bash_profile 
