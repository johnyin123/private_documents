#!/bin/bash
VERSION+=("fae9318[2023-04-19T14:33:57+08:00]:motd.sh")
# Not bash
[ -n "${BASH_VERSION:-}" ] || return 0
# Not an interactive shell?
[[ $- == *i* ]] || return 0
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
mem_usage=$(LC_ALL=C LANG=C free -m | grep Mem | awk '{ printf("%3.2f%%", $3*100/$2) }')
swap_usage=$(LC_ALL=C LANG=C free -m | awk '/Swap/{printf "%.2f%%",$3/($2+1)*100}')

#Processes
processes=$(ps aux | wc -l)

#User
users=$(users | wc -w)
USER=$(whoami)

#System fs usage
Filesystem=$(timeout 3 df --local -h | awk '/^\/dev/{print $6}')

#Interfaces
INTERFACES=$(ls /sys/class/net/)
uuid=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
serial="$(cat /sys/class/dmi/id/product_serial 2>/dev/null)"
product="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
[[ -r /etc/os-release ]] && source /etc/os-release
head="$PRETTY_NAME ($date)"

printf "%s\n" "==============================================================================="
[ -f "/etc/logo.txt" ] && logo=/etc/logo.txt || logo=/dev/null
exec {FD}<${logo}
{
    printf "$head\n"
    printf "%s\n" "-----------------------------------------------------------"
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
    printf "%s\n" "-----------------------------------------------------------"
    printf "Filesystem          Total     Usage\n"
    for f in $Filesystem
    do
        Usage=$(timeout 3 df -h | awk '{if($NF=="'''$f'''") printf "%-10s%s",$2,$5}')
        printf "%-20s%s\n" $f "$Usage"
    done
    printf "%s\n" "-----------------------------------------------------------"
    printf "Interface           MAC Address         IP Address\n"
    for i in $INTERFACES
    do
        [ "$i" = "lo" ] && continue
        [ "$i" = "bonding_masters" ] && continue
        MAC=$(ip ad show dev $i | grep "link/ether" | awk '{print $2}')
        IP=$(ip ad show dev $i | awk '/scope global/ {print $2}')
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
printf "%s\n" "==============================================================================="
