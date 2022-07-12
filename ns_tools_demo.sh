./ssh_tunnel.sh -L br-sy -R br-data.149 -s root@<IPADDR>
./br-hostapd.sh -s wlan0 -b br-sy
./netns_shell.sh -i <YOU IP>/24 -n baidu -b br-sy
./wireguard_netns.sh -w dalian -c wg0.conf -n dalian
