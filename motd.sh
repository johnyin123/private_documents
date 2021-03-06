#!/bin/bash
VERSION+=("motd.sh - aa8f952 - 2021-04-16T10:56:58+08:00")
date=$(date "+%F %T")
kernel=$(uname -r)
hostname=${HOSTNAME:-$(hostname)}
#Cpu load
load1_5_15=$(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg)
#System uptime
uptime=$(cut -f1 -d. /proc/uptime)
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
uuid=$(dmidecode -s system-uuid 2>/dev/null)
serial="$(dmidecode -s system-serial-number 2>/dev/null)"
product="$(dmidecode -s system-product-name 2>/dev/null)"
[[ -r /etc/os-release ]] && source /etc/os-release
head="$PRETTY_NAME ($date)"

echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"

exec {FD}</etc/logo.txt
{
    printf "$head\n"
    printf "%s\n" "----------------------------------------------"
    printf "Product name:       %s\n" "$product"
    printf "Serial number:      %s\n" "$serial"
    printf "Kernel Version:     %s\n" "$kernel"
    printf "UUID:               %s\n" "$uuid"
    printf "HostName:           %s\n" "$hostname"
    printf "System Load:        %s\n" "$load1_5_15"
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
        [ "$i" = "bonding_masters" ] && continue
        MAC=$(ip ad show dev $i | grep "link/ether" | awk '{print $2}')
        IP=$(ip ad show dev $i | awk '/inet / {print $2}')
        for j in ${IP}
        do
            printf "%-20s%-20s%s\n" "$i" "$MAC" "$j"
        done
    done

} | while IFS= read -r line; do 
    IFS= read -r line2 <&${FD}
    str="$(printf "%s" "${line}" | sed -r 's/\x1B\[([0-9];)?([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g')"
    slen=${#str}
    len=${#line}
    printf "%-$((60+len-slen))s%s\033[m\n" "$line" "$line2"
done
exec {FD}>&-
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
