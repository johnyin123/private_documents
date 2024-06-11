#!/bin/bash
# 2021 devmfc
Y='\e[0;93m' D='\e[0m' R='\e[0;31m' G='\e[1;32m' W='\e[1;37m'
echo -e "Connect to wifi network ${W}wlan0${D}: ${Y}$(udevadm info /sys/class/net/wlan0|grep -oP "(?<=ID_NET_DRIVER=).*")${D}"
WIFI_SSID_ARR=()

if ! ls /sys/class/net/wlan* &>/dev/null; then
	echo "no wlan interface found"
	exit -1
fi

echo -en "Scanning for available wifi networks, please wait..."
#'grep' -Po '(BSS \K[0-9a-f]{2}:[^(]*|signal: -\K[0-9]*|freq: \K[25]|SSID: \K.*)'|paste -d'|' - - - -

readarray -t WIFI_SSID_ARR <<<$(iw dev wlan0 scan|grep -Po "(?<=SSID: )[^\s]+.*")

WIFI_SSID_ARR=('' "${WIFI_SSID_ARR[@]}")

echo -e "\u001b[0G                                                                             \u001b[0G"
for (( i=1 ; i<${#WIFI_SSID_ARR[@]};i++ )) do
	echo "$i: ${WIFI_SSID_ARR[i]}"
done

read -p "Choose wifi SSID: "

SSID=${WIFI_SSID_ARR[$REPLY]}

echo -en "Please enter password/pre shared key for [$Y${SSID}$D]:"
read -s PSK

echo -e "\nTrying to authenticate, please wait..."

wpa_passphrase "${SSID}" "${PSK}"|grep -v "#psk" > wpa_supplicant_tmp.conf
systemctl stop wpa_supplicant@wlan0.service


PIPE=$(mktemp -u)
mkfifo $PIPE
(wpa_supplicant -Dwext -cwpa_supplicant_tmp.conf -iwlan0 > $PIPE ) &
PID=$!
ERR=0

FAIL=".*pre-shared key may be incorrect.*"
SUCCESS=".*Key negotiation completed.*"

while read -t 30 line ; do
	ERR=$?
	if [[ $ERR != 0 ]]; then echo "err $ERR"; break;fi
	if [[ $line =~ $SUCCESS ]]; then echo "auth ok"; break; fi
	if [[ $line =~ $FAIL ]]; then ERR=-2; echo "Auth failed, pre-shared key may be incorrect."; break; fi
done < $PIPE

if [[ $ERR != 0 ]]; then
	kill $PID
	rm $PIPE
	rm wpa_supplicant_tmp.conf
	echo -e "$RFailed...$D"
	exit -1
fi

echo "Saving wifi config..."
if [[ ! -f wpa_supplicant.conf ]]; then
	echo "ctrl_interface=/run/wpa_supplicant" > wpa_supplicant.conf
	echo -e "update_config=1\n" >> wpa_supplicant.conf
fi

cat wpa_supplicant_tmp.conf >> wpa_supplicant.conf
rm wpa_supplicant_tmp.conf
ln -fs $(realpath wpa_supplicant.conf) /etc/wpa_supplicant/wpa_supplicant-wlan0.conf


echo "Try getting ip from DHCP..."
dhclient wlan0
ip_address=$(ip a|'grep' -Po -m 1 "(?<=inet\s)[0-9.]+(?=.*wlan)")
echo -e "\nReady. Wifi address: $G$ip_address$D"
