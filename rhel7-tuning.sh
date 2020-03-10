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
 
#set ssh
sed -i 's/#UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' /etc/ssh/sshd_config
sed -i 's/#Port.*/Port 60022/g' /etc/ssh/sshd_config
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
net.ipv4.ip_local_port_range = 1024 65530
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

cat >/etc/motd.sh<<"EOF"
#!/bin/bash
date=$(date "+%F %T")
kernel=$(uname -r)
hostname=$(echo $HOSTNAME)
#Cpu load
load1=$(cat /proc/loadavg | awk '{print $1}')
load5=$(cat /proc/loadavg | awk '{print $2}')
load15=$(cat /proc/loadavg | awk '{print $3}')
#System uptime
uptime=$(cat /proc/uptime | cut -f1 -d.)
upDays=$((uptime/60/60/24))
upHours=$((uptime/60/60%24))
upMins=$((uptime/60%60))
upSecs=$((uptime%60))
up_lastime=$(date -d "$(awk -F. '{print $1}' /proc/uptime) second ago" +"%Y-%m-%d %H:%M:%S")
#Memory Usage
mem_usage=$(free -m | grep Mem | awk '{ printf("%3.2f%%", $3*100/$2) }')
swap_usage=$(free -m | awk '/Swap/{printf "%.2f%%",$3/($2+1)*100}')

#Processes
processes=$(ps aux | wc -l)

#User
users=$(users | wc -w)
USER=$(whoami)

#System fs usage
Filesystem=$(df -h | awk '/^\/dev/{print $6}')

#Interfaces
INTERFACES=$(ls /sys/class/net/)
uuid=$(dmidecode -s system-uuid)
[[ -r /etc/os-release ]] && source /etc/os-release
head="$PRETTY_NAME ($date)"

echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
exec 6</etc/logo.txt
{
    printf "$head\n"
    printf "%s\n" "----------------------------------------------"
    printf "Kernel Version:     %s\n" $kernel
    printf "UUID:               %s\n" $uuid
    printf "HostName:           %s\n" $hostname
    printf "System Load:        %s %s %s\n" $load1, $load5, $load15
    printf "System Uptime:      %s "days" %s "hours" %s "min" %s "sec"\n" $upDays $upHours $upMins $upSecs
    printf "Memory Usage:       %s  Swap Usage:      %s\n" $mem_usage $swap_usage
    printf "Login Users:        %s\n" $users
    printf "User:               %s\n" $USER
    printf "Processes:          %s\n" $processes
    printf "%s\n" "---------------------------------------------"
    printf "Filesystem          Usage\n"
    for f in $Filesystem
    do
        Usage=$(df -h | awk '{if($NF=="'''$f'''") print $5}')
        printf "%-20s%s\n" $f $Usage
    done
    printf "%s\n" "---------------------------------------------"
    printf "Interface           MAC Address         IP Address\n"
    for i in $INTERFACES
    do
        [ "$i" = "lo" ] && continue
        MAC=$(ip ad show dev $i | grep "link/ether" | awk '{print $2}')
        IP=$(ip ad show dev $i | awk '/inet / {print $2}')
        for j in ${IP}
        do
            printf "%-20s%-20s%s\n" $i $MAC $j
        done
    done

} | while IFS= read -r line; do 
    IFS= read -r line2 <&6
    str="$(printf "%s" "${line}" | sed -r 's/\x1B\[([0-9];)?([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g')"
    slen=${#str}
    len=${#line}
    printf "%-$((60+len-slen))s%s\033[m\n" "$line" "$line2"
done
exec 6<&-
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
EOF
chmod 755 /etc/motd.sh
cat >> /etc/profile << EOF
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$"
export readonly PROMPT_COMMAND='{ msg=\$(history 1 | { read x y; echo \$y; });user=\$(whoami); echo \$(date "+%Y-%m-%d%H:%M:%S"):\$user:`pwd`/:\$msg ---- \$(who am i); } >> \$HOME/.history'
set -o vi
sh /etc/motd.sh
EOF

systemctl set-default multi-user.target

chkconfig 2>/dev/null | egrep -v "crond|sshd|network|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}' | bash
systemctl list-unit-files | grep service | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}' | bash

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
