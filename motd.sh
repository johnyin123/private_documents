#!/bin/bash
date=$(date "+%F %T")
head="System Time:        $date"
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

uuid=$(dmidecode | grep UUID | awk '{print $2}')
#Interfaces
INTERFACES=$(ip -4 ad | grep 'state ' | awk -F":" '!/^[0-9]*: ?lo/ {print $2}')
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "$head"
echo "----------------------------------------------"
printf "Kernel Version:     %s\n" $kernel
printf "HostName:           %s\n" $hostname
printf "UUID:               %s\n" ${uuid}
printf "System Load:        %s %s %s\n" $load1, $load5, $load15
printf "System Uptime:      %s "days" %s "hours" %s "min" %s "sec"\n" $upDays $upHours $upMins $upSecs
printf "Memory Usage:       %s     Swap Usage:      %s\n" $mem_usage $swap_usage
printf "Login Users:        %s\n" $users
printf "User:               %s\n" $USER
printf "Processes:          %s\n" $processes
echo  "---------------------------------------------"
printf "Filesystem          Usage\n"
for f in $Filesystem
do
    Usage=$(df -h | awk '{if($NF=="'''$f'''") print $5}')
    printf "%-20s%s\n" $f $Usage
done
echo  "---------------------------------------------"
printf "Interface           MAC Address         IP Address\n"
for i in $INTERFACES
do
    MAC=$(ip ad show dev $i | grep "link/ether" | awk '{print $2}')
    IP=$(ip ad show dev $i | awk '/inet / {print $2}')
    printf "%-20s%-20s" $i $MAC
    for i in ${IP}
    do
        printf "%s " $i
    done
    printf "\n"
done
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo
