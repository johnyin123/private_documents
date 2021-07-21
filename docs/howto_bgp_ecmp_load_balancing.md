# How to build a load balancer with BGP and ECMP using VyOS

According to this cloudflare blog article ["Load Balancing without Load Balancers"](https://blog.cloudflare.com/cloudflares-architecture-eliminating-single-p/), we can build a rock-solid load balancer only using a router. All the magic comes from [BGP](https://en.wikipedia.org/wiki/Border_Gateway_Protocol) and [Equal-Cost Multi-Path routing](https://en.wikipedia.org/wiki/Equal-cost_multi-path_routing).

In this howto, I will use `bird` as BGP router on linux instance (ie. servers).

## Test environment
I use GNS3 with this architecture :

![architecture](https://gist.githubusercontent.com/bufadu/0c3ba661c141a2176cd048f65430ae8d/raw/b93bc7172ae41ea254fb3b2606d272850c84f600/zz-archi.png)

- `ISP` is a VyOS instance version 1.1.7
- `VyOSTesting` is a VyOS testing build. See note about ECMP on linux
- `client` is an alpine linux instance
- `server-1` and `server-2` are alpine linux instance with bird
- `internet` is just a link to my lab lan to get access to internet. `client` will be used to actually test routing and load balancing.

### What are we going to build and how it works ?
`AS 65000` will be our internet service provider. We will build a BGP session between our router (EdgeRouter) and ISP router. The network `172.16.42.2/31` will be used between these two routers.

`server-1` and `server-2` will be in the `10.12.12.0/24` private LAN. Both servers will announce the same public IP (10.13.13.1) to `EdgeRouter` using BGP (this is why we speak about anycasting). Incoming traffic from internet to this public IP will be routed to `server-1` or `server-2` depending of a hash based on source address, destination address and destination port.

### ECMP and Linux
ECMP is [broken](https://www.reddit.com/r/networking/comments/4q3wmq/ipv4_flow_based_ecmp_broken_in_linux_kernels_36/) under linux until kernel 4.4. VyOS 1.1.7 runs on 3.13. That's why I'm using VyOS testing release for the datacenter router.

## ISP router configuration
I need a router instance that act as my ISP router. Configuration is fairly simple :
```
# interfaces configurations
set interfaces ethernet eth0 address 'dhcp'
set interfaces ethernet eth1 address '10.0.0.254/24'
set interfaces ethernet eth2 address '172.16.42.2/31'

# source nat to let 'client' instance reach internet (optional)
set nat source rule 100 outbound-interface 'eth0'
set nat source rule 100 source address '10.0.0.0/24'
set nat source rule 100 translation address 'masquerade'

# source nat let my network reach internet (optional)
set nat source rule 200 outbound-interface 'eth0'
set nat source rule 200 source address '172.16.42.3/31'
set nat source rule 200 translation address 'masquerade'

# Simple BGP configuration
set protocols bgp 65000 neighbor 172.16.42.3 remote-as '65500'
set protocols bgp 65000 neighbor 172.16.42.3 update-source '172.16.42.2'
set protocols bgp 65000 network '0.0.0.0/0'
set protocols bgp 65000 parameters router-id '172.16.42.2'

# DNS server for 'client instance'
set service dns forwarding cache-size '0'
set service dns forwarding listen-on 'eth1'
set service dns forwarding name-server '8.8.8.8'
set service dns forwarding name-server '4.2.2.2'
```

## Edge router configuration
```
set interfaces ethernet eth0 address '172.16.42.3/31'
set interfaces ethernet eth1 address '10.12.12.254/24'

set nat source rule 100 outbound-interface 'eth0'
set nat source rule 100 source address '10.12.12.0/24'
set nat source rule 100 translation address 'masquerade'

set protocols bgp 65500 maximum-paths ibgp '2'
set protocols bgp 65500 neighbor 10.12.12.1 remote-as '65500'
set protocols bgp 65500 neighbor 10.12.12.1 update-source '10.12.12.254'
set protocols bgp 65500 neighbor 10.12.12.2 remote-as '65500'
set protocols bgp 65500 neighbor 10.12.12.2 update-source '10.12.12.254'
set protocols bgp 65500 neighbor 172.16.42.2 remote-as '65000'
set protocols bgp 65500 neighbor 172.16.42.2 update-source '172.16.42.3'
set protocols bgp 65500 parameters router-id '172.16.42.3'

set service dns forwarding cache-size '0'
set service dns forwarding listen-on 'eth1'
set service dns forwarding name-server '8.8.8.8'
```

## Servers configuration
Under alpine linux :
```
apk update
apk install bird
apk install nginx
```

`/etc/network/interfaces` is like :
```
auto lo
iface lo inet loopback

iface lo inet static
        address 10.13.13.1
        netmask 255.255.255.0

auto eth0
iface eth0 inet static
        address 10.12.12.1
        netmask 255.255.255.0
        gateway 10.12.12.254
```
Change `eth0` address `10.12.12.1` to `10.12.12.2` on server-2. `10.13.13.1` is configured on the local loopback interface.


Edit /etc/bird.conf as :
```
protocol kernel {
        persist;
        scan time 20;
        export all;
}

protocol device {
        scan time 10;
}

protocol static {
}

protocol static static_bgp {
        import all;
        route 10.13.13.1/32 reject;
}

protocol bgp {
        local as 65500;
        neighbor 10.12.12.254 as 65500;
        import none;
        export where proto = "static_bgp";
}
```

Start `Bird` with `/etc/init.d/bird start` and on `Edge router` BGP session should mount:
```
vyos@egderouter:~$ show ip bgp
BGP table version is 0, local router ID is 172.16.42.3
Status codes: s suppressed, d damped, h history, * valid, > best, i - internal,
              r RIB-failure, S Stale, R Removed
Origin codes: i - IGP, e - EGP, ? - incomplete

   Network          Next Hop            Metric LocPrf Weight Path
*> 0.0.0.0          172.16.42.2              0             0 65000 i
*>i10.13.13.1/32    10.12.12.1                    100      0 i
* i                 10.12.12.2                    100      0 i

Total number of prefixes 2
```

On ISP router :
```
vyos@isprouter:~$ show ip bgp
BGP table version is 0, local router ID is 172.16.42.2
Status codes: s suppressed, d damped, h history, * valid, > best, i - internal,
              r RIB-failure, S Stale, R Removed
Origin codes: i - IGP, e - EGP, ? - incomplete

   Network          Next Hop            Metric LocPrf Weight Path
*> 0.0.0.0          192.168.100.254          0         32768 i
*> 10.13.13.1/32    172.16.42.3                            0 65500 i

Total number of prefixes 2
```


Quick and dirty nginx configuration :
```
cat <<EOF > /etc/nginx/conf.d/default.conf
server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /tmp;
}
EOF

echo server-1 > /tmp/file
# OR
echo server-2 > /tmp/file

/etc/init.d/nginx restart
```

Once done, on `client` instance :
```
# curl 10.13.13.1/file
server-1
```

Woohoo, it works. Now change client ip to 10.0.0.2 and boom :
```
# curl 10.13.13.1/file
server-2
```

The load balancing is working !!

### Remove one server off the load balancer pool
Simply halt bird :
```
client:~# curl 10.13.13.1/file
server-2

server-2:~# /etc/init.d/bird stop

client:~# curl 10.13.13.1/file
server-1
```

### Lowering server priority in the pool
By adjusting `bgp_local_pref` in bird, you can adjust server priority.

On server-2 in /etc/bird.conf, add:
```
protocol bgp {
[...]
       default bgp_local_pref 50;
[...]
}
```
Reload bird and then the route will have lower priority :
```
   Network          Next Hop            Metric LocPrf Weight Path
*> 0.0.0.0          172.16.42.2              0             0 65000 i
* i10.13.13.1/32    10.12.12.2                     50      0 i
*>i                 10.12.12.1                    100      0 i

```

## Variant without advertising public IP
What if I can't/wan't set public IP on servers ?

On `EdgeRouter`, add the following configuration
```
# destination nat to forward http traffic to 10.13.13.1
set nat destination rule 10 description 'http server'
set nat destination rule 10 destination address '172.16.42.3'
set nat destination rule 10 destination port '80'
set nat destination rule 10 inbound-interface 'any'
set nat destination rule 10 protocol 'tcp'
set nat destination rule 10 translation address '10.13.13.1'
# don't let our internal bgp session leak using policy
set policy route-map AS65500-OUT rule 20 action 'deny'
# add policy to our bgp session
set protocols bgp 65500 neighbor 172.16.42.2 route-map export 'AS65500-OUT'
```
