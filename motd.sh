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
        [ "$i" = "bonding_masters" ] && continue
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
