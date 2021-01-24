#!/bin/bash

function wait_alive {
	local ip=$1
	n=1  
	while (( $n <= 60 ))
	do
		ping -c1 -W1 $ip >/dev/null 2>&1 && { echo -en "\r"; return 0; }
		echo -n .
		(( n++ ))
		sleep 1 
	done
	echo -en "\r"
	return 1
}
function restart {
	local name=$1
	local ip=$2
	echo "start[$ip] $name"
	virsh start $name > /dev/null 2>&1
	wait_alive $ip
	if [[ $? != 0 ]]
	then
		 echo "[$ip] $name ERROR"
	else
		 echo "[$ip] $name OK"
	fi
}
for i in $(seq 2 99)
do
	vm_name=$(virsh list --all --title | grep "vm-test$i[ |\t]" | awk '{print $2}')
	vm_ip=10.0.2.$i
	ping -c1 -W1 $vm_ip >/dev/null 2>&1 && echo "[$vm_ip] $vm_name alive" || restart $vm_name $vm_ip 
done

