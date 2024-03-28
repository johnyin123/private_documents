echo "10.0.1.1" |  sed -E 's/([0-9]{1,3}\.)([0-9]{1,3}\.)([0-9]{1,3}\.)([0-9]{1,3})/XXX.XXX.\3\4/g'

read range
nmap -sn $range |cut -d " " -f 5|grep -v latency|grep -v addresse > /tmp/ips_scanned.txt
nmap -sL $range |cut -d " " -f 5|grep -v addresses > /tmp/possible_ips.txt
echo "Unused IP Addresses using nmap -sn for detection. Try a port scan to drill down further"
awk 'FNR==NR{a[$1]=$0;next} !($1 in a) {print $1, $4}' /tmp/ips_scanned.txt /tmp/possible_ips.txt|more

