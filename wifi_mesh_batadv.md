

# - WiFi Access Point bridged to mesh

In this part you will convert the bridge node into an access point and enable the WiFi traffic coming over the Access Point to access the mesh network by bridging the Access Point interface into the configured bridge interface br0.

Note the configuration below leaves interface eth0 in the configuration, so you can use both the Ethernet connection and WiFi connection to bridge onto the mesh network.

## Configuring the Access point and bridging to br0 interface

1. Install additional software to run the access point using command ```sudo apt-get install -y hostapd```
2. Edit file **sudo vi /etc/hostapd/wlan1.conf** as root user and set the content to:

    ```text
    interface=wlan1
    bridge=br0
    hw_mode=g
    channel=7
    wmm_enabled=0
    macaddr_acl=0
    auth_algs=1
    ignore_broadcast_ssid=0
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=TKIP
    rsn_pairwise=CCMP
    ssid=raspimesh
    wpa_passphrase=passw0rd
    ```

    You can change the SSID and the passphrase to something you'd prefer, as these configure the access point your devices will connect to.

    The above configuration sets up a 2.4GHz network on channel 7, again, you can change all the details to match your WiFi dongle and preferred network.  You can find details of all possible options for the config file [here](https://w1.fi/cgit/hostap/plain/hostapd/hostapd.conf)

3. Edit file **/etc/default/hostapd** as root user.  ```sudo vi /etc/default/hostapd``` or ```sudo nano /etc/default/hostapd``` and set the content to:

    ```text
    # Defaults for hostapd initscript
    #
    # See /usr/share/doc/hostapd/README.Debian for information about alternative
    # methods of managing hostapd.
    #
    # Uncomment and set DAEMON_CONF to the absolute path of a hostapd configuration
    # file and hostapd will be started during system boot. An example configuration
    # file can be found at /usr/share/doc/hostapd/examples/hostapd.conf.gz
    #
    DAEMON_CONF=""

    # Additional daemon options to be appended to hostapd command:-
    #   -d   show more debug messages (-dd for even more)
    #   -K   include key data in debug messages
    #   -t   include timestamps in some debug messages
    #
    # Note that -B (daemon mode) and -P (pidfile) options are automatically
    # configured by the init.d script and must not be added to DAEMON_OPTS.
    #
    DAEMON_OPTS="-B"
    ```

    notice the DAEMON_OPTS option.  This should not need to be set, but I noticed in the latest version of Raspbian lite, the -B options is not set in the startup script, which causes the service to time out and be restarted, which resets all WiFi connections to the Access Point.
4. Modify the last line of file **/etc/dhcpcd.conf** as root user and add wlan1 to the list of denied interfaces:

    ```text
    denyinterfaces wlan0 eth0 bat0 wlan1
    ```

5. Update the **~/start-batman-adv.sh** file ```vi ~/start-batman-adv.sh``` or ```nano ~/start-batman-adv.sh```, so the file contains the following:

    ```text
    #!/bin/bash

    # Tell batman-adv which interface to use
    sudo batctl if add wlan0
    sudo ifconfig bat0 mtu 1468

    sudo brctl addbr br0
    sudo brctl addif br0 bat0 eth0

    # Tell batman-adv this is a gateway client
    sudo batctl gw_mode client

    # Activates the interfaces for batman-adv
    sudo ifconfig wlan0 up
    sudo ifconfig bat0 up

    # Restart DHCP now bridge and mesh network are up
    sudo dhclient -r br0
    sudo dhclient br0
    ```

6. Enable the access point service on wlan1 interface using command ```sudo systemctl enable hostapd@wlan1.service```
7. Reboot the pi using command ```sudo reboot -n```

When the Pi reboots you should be able to see a new WiFi network available and devices should be able to join it, using the passphrase you set in the /etc/hostapd/wlan1.conf file.

## Verifying the setup

You can do a number of steps to verify that the configuration has been successfully created and applied.

1. Run command ```ifconfig``` top check all the interfaces are up and running OK.  You should see output similar to :

    ```text
    bat0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1468
            inet6 fe80::4816:e8ff:fe16:a3ba  prefixlen 64  scopeid 0x20<link>
            ether 4a:16:e8:16:a3:ba  txqueuelen 1000  (Ethernet)
            RX packets 1481  bytes 462785 (451.9 KiB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 1632  bytes 270351 (264.0 KiB)
            TX errors 0  dropped 3 overruns 0  carrier 0  collisions 0

    br0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1468
            inet 192.168.199.53  netmask 255.255.255.0  broadcast 192.168.199.255
            inet6 fe80::11ac:9f5e:3034:e59d  prefixlen 64  scopeid 0x20<link>
            ether 4a:16:e8:16:a3:ba  txqueuelen 1000  (Ethernet)
            RX packets 360  bytes 42545 (41.5 KiB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 281  bytes 51671 (50.4 KiB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    eth0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
            ether b8:27:eb:e8:18:b0  txqueuelen 1000  (Ethernet)
            RX packets 0  bytes 0 (0.0 B)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 0  bytes 0 (0.0 B)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
            inet 127.0.0.1  netmask 255.0.0.0
            inet6 ::1  prefixlen 128  scopeid 0x10<host>
            loop  txqueuelen 1000  (Local Loopback)
            RX packets 0  bytes 0 (0.0 B)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 0  bytes 0 (0.0 B)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet6 fe80::ba27:ebff:febd:4de5  prefixlen 64  scopeid 0x20<link>
            ether b8:27:eb:bd:4d:e5  txqueuelen 1000  (Ethernet)
            RX packets 3674  bytes 758584 (740.8 KiB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 2652  bytes 500450 (488.7 KiB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    wlan1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet6 fe80::d67b:b0ff:fe0e:800e  prefixlen 64  scopeid 0x20<link>
            ether d4:7b:b0:0e:80:0e  txqueuelen 1000  (Ethernet)
            RX packets 1798  bytes 312112 (304.7 KiB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 1728  bytes 506350 (494.4 KiB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
            ```

    Notice:
    - you can see both wlan0 and wlan1 and both are running
    - br0 is the only interface with a 192.168.199.x address

2. Command ```sudo brctl show``` show show bat0, wlan1 and eth0 as bridged interfaces to br0:

    ```text
    bridge name bridge id       STP enabled interfaces
    br0     8000.4a16e816a3ba   no      bat0
                                        eth0
                                        wlan1
    ```

3. Command ```iw wlan1 info``` show the details of the access point running on wlan1:

    ```text
    Interface wlan1
        ifindex 5
        wdev 0x100000001
        addr d4:7b:b0:0e:80:0e
        ssid raspimesh
        type AP
        wiphy 1
        channel 7 (2442 MHz), width: 20 MHz, center1: 2442 MHz
        txpower 31.00 dBm
    ```

You can also run the commands ```sudo batctl if``` and ```sudo batctl n``` to verify the mesh configuration is still OK.

# - WiFi Connected Gateway

This section of the workshop will enable your gateway to connect to your home/office network via WiFi and route mesh traffic over the WiFi connection instead of using an Ethernet connection,  which was setup in part 1.

You need to have a supported USB WiFi dongle to add a second WiFi interface to the Raspberry Pi.  Some USB WiFi dongles need additional drivers to be installed before working with a Raspberry Pi - check the manufacturer website or other community support sites if you need help.

The configuration presented will use wlan0 as the mesh WiFi interface and wlan1 as the home/office WiFi interface.  

When you connect a WiFi dongle it is often assigned wlan0, then the internal WiFi becomes wlan1.  If you need the USB WiFi dongle to be the interface to connect to the home/office network then you should replace wlan0 with wlan 1 in all the previous configuration completed in part 1 and switch wlan0 and wlan1 in the following configuration.

## Setting up the network connection

To connect to a WiFi network the raspberry pi uses a configuration file /etc/wpa_supplicant/wpa_supplicant.conf.  

1. Edit /etc/wpa_supplicant/wpa_supplicant.conf as root user and change the content to be similar to the following, noting the comments below:

    ```text
    ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
    update_config=1
    country=GB
    network={
        ssid="network name"
        scan_ssid=1
        psk="password"
    }
    ```

    - leave the country code as you set with the raspi-config (which should be the country you are located in).  If you need to lookup the correct country code, the a list of the ISO 3166 country codes are [here](https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes) - select the Alpha-2 column for valid codes.
    - set the **network name** to be the name of the network you want to join
    - set the **password** to the network password you want to join

## Updating the mesh traffic routing for WiFi

The rules in file start-batman-adv.sh need to be updated to route traffic to the wlan1 interface rather than the eth0 interface.

1. Edit file ~/start-batman-adv.sh and set the content to:

    ```text
    #!/bin/bash
    # batman-adv interface to use
    sudo batctl if add wlan0
    sudo ifconfig bat0 mtu 1468

    # Tell batman-adv this is an internet gateway
    sudo batctl gw_mode server

    # Enable port forwarding between eth0 and bat0
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo iptables -t nat -A POSTROUTING -o wlan1 -j MASQUERADE
    sudo iptables -A FORWARD -i wlan1 -o bat0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -i bat0 -o wlan1 -j ACCEPT

    # Activates the interfaces for batman-adv
    sudo ifconfig wlan0 up
    sudo ifconfig bat0 up # bat0 is created via the first command
    sudo ifconfig bat0 192.168.199.1/24
    ```

## Verifying the configuration

1. Shutdown the gateway raspberry pi with command ```sudo shutdown -h now```.  Wait for the pi to shutdown then remove the power cable
2. Inset the WiFi USB dongle
3. Reconnect the power to the Raspberry Pi and wait for it to boot.
4. Connect to the pi via ssh
5. Run command ```ifconfig``` and check you can see both wlan0 and wlan1 interfaces.
6. Run command ```iwconfig``` and check you see something similar to:

    ```text
    wlan0     IEEE 802.11  ESSID:"bi-raspi-mesh"  
            Mode:Ad-Hoc  Frequency:2.462 GHz  Cell: B2:7A:83:D4:C2:B9
            Tx-Power=31 dBm
            Retry short limit:7   RTS thr:off   Fragment thr:off
            Power Management:on

    lo        no wireless extensions.

    wlan1     IEEE 802.11  ESSID:"INNES"  
            Mode:Managed  Frequency:2.437 GHz  Access Point: 00:23:6C:BF:51:47
            Bit Rate=39 Mb/s   Tx-Power=31 dBm
            Retry short limit:7   RTS thr:off   Fragment thr:off
            Power Management:on
            Link Quality=44/70  Signal level=-66 dBm  
            Rx invalid nwid:0  Rx invalid crypt:0  Rx invalid frag:0
            Tx excessive retries:149  Invalid misc:0   Missed beacon:0

    bat0      no wireless extensions.

    eth0      no wireless extensions.
    ```

    noticing:

    - wlan0 is in Ad-Hoc mode and has the mesh network ESSID
    - wlan1 is in Managed mode and is connected to your home/office network ESSID (which you entered in wpa_supplicant)

7. Check the mesh configuration is still OK, as you did in part 1 with commands  ```sudo batctl if``` and ```sudo batctl n```
8. From your gateway raspberry pi, ssh to another node on the mesh (or connect your laptop to the bridged node) and on a command line on the mesh node enter command ```ping www.ibm.com -c 5``` to verify that routing to the internet and back is working correctly.

You now have your gateway working using a WiFi connection to your home/office network.