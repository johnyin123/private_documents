gen_keepalive_conf() {
    local state=${1}
    local vip=${2:-192.168.1.10/24}
    local priority= weight=50 router_id=nginx interface=eth0
    case "${state}" in
        MASTER) priority=110;;
        BACKUP) priority=100;;
        *)      echo "state must MASTER/BACKUP" >&2; return 1;;
    esac
    echo "/etc/keepalived/keepalived.conf" >&2
    cat <<EOF
global_defs {
    router_id ${router_id}
}
# Script to check whether Nginx is running or not
vrrp_script check_nginx {
    script "/bin/check_nginx.sh"
    interval 2
    weight ${weight}
}
# Virtual interface - The priority specifies the order in which
# the assigned interface to take over in a failover
vrrp_instance VI_01 {
    state ${state}
    interface ${interface}
    virtual_router_id 151
    priority ${priority}
    virtual_ipaddress {
        ${vip} 
    }
    track_script {
        check_nginx
    }
    authentication {
        auth_type AH
        auth_pass secret_pass
    }
}
EOF
}
echo "/bin/check_nginx.sh" >&2
cat <<'EOF'
#!/bin/sh
if [ -z "`pidof nginx`" ]; then
  exit 1
fi
EOF
gen_keepalive_conf MASTER 192.168.1.10/24
echo "========================" >&2
gen_keepalive_conf BACKUP 192.168.1.10/24
