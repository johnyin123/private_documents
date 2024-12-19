#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("2348661[2024-12-19T15:48:09+08:00]:post-01-apiserver-ha.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
        -m|--master         *  ${G}<ip>${N}      all master nodes, multi input nodes
        -w|--worker         *  ${G}<ip>${N}      all worker nodes, multi input nodes
        --vip               *  ${G}<ip>${N}      keepalived vrrp vip
        --api_srv              ${G}<str>${N}     api server dnsname, with no PORT
                                                exam: k8s.tsd.org, if unset then use vip
        --insec_registry       ${G}<str>${N}     insecurity registry(no auth)
                                                default, registry.local
        -q|--quiet
        -l|--log ${G}<int>${N} log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        exam:
        ${SCRIPTNAME} -m 172.16.0.150 -m 172.16.0.151 -m 172.16.0.152 --vip 172.16.0.155 --api_srv k8s.tsd.org
EOF
)"; echo -e "${usage_doc}"
    exit 1
}

gen_haproxy_cfg() {
    local masters="${*}"
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats

defaults
    mode                    tcp
    log                     global
    option                  tcplog
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout check           10s
    maxconn                 3000

listen stats
    mode   http
    bind   :10086
    stats   enable
    stats   uri     /admin?stats
    stats   auth    admin:admin
    stats   admin   if TRUE

frontend  k8s_https
    bind      *:60443
    mode      tcp
    maxconn   2000
    default_backend     kube_api

backend kube_api
    balance roundrobin
$(for i in ${masters}; do
echo "    server  ${i}  ${i}:6443  check port 6443 inter 10000 fall 2 rise 2 weight 1"
done)
EOF
}

gen_nginx_cfg() {
    local masters="${*}"
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
upstream kube-api {
    hash \$remote_addr consistent;
$(for i in ${masters}; do
echo "    server $i:6443 max_fails=3 fail_timeout=1s;"
done)
}
server {
    listen 60443;
    access_log off;
    proxy_connect_timeout 1s;
    proxy_pass kube-api;
}
EOF
}

gen_keepalived_cfg() {
    local id=${1}
    local vip=${2}
    local dev=${3}
    local src=${4}
    shift 4
    local real_ips="${*}"
    local ip=""
    passwd=$(gen_passwd)
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
global_defs {
    router_id ${id}
    vrrp_skip_check_adv_addr
    vrrp_garp_interval 0
    vrrp_gna_interval 0
}
vrrp_instance kube-api-vip {
    state BACKUP
    priority 100
    interface ${dev}
    virtual_router_id 60
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass passwd4kube-api-${passwd}
    }
    unicast_src_ip ${src}
    unicast_peer {
$(for ip in ${real_ips}; do
    [ "${src}" == "${ip}" ] && continue
    cat<<EO_REAL
        ${ip}
EO_REAL
done)
    }
    virtual_ipaddress {
        ${vip}
    }
    # notify_master ""
    # notify_backup ""
    # notify_stop ""
}
EOF
}

apilb_yaml() {
    local registry=${1}
    vinfo_msg <<EOF
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: kube-system
spec:
  hostNetwork: true
  containers:
    - name: nginx
      image: ${registry}/nginx:bookworm
      command: ["/bin/sh", "-c"]
      args:
        - |
          sed -i "/worker_processes/d" /etc/nginx/nginx.conf
          exec /usr/sbin/nginx -g "daemon off;worker_processes 1;"
      volumeMounts:
        - mountPath: /etc/nginx/stream-enabled/api.conf
          name: nginx-conf
          readOnly: true
    - name: keepalived
      image: ${registry}/keepalived:bookworm
      securityContext:
        privileged: true
      command:
        - /usr/sbin/keepalived
        - -D
        - -n
      volumeMounts:
        - mountPath: /etc/keepalived/keepalived.conf
          name: keepalived-cfg
          readOnly: true
  volumes:
    - hostPath:
        path: /etc/kubernetes/api.conf
        type: FileOrCreate
      name: nginx-conf
    - hostPath:
        path: /etc/kubernetes/keepalived.conf
        type: FileOrCreate
      name: keepalived-cfg
EOF
}

main() {
    local masters=() worker=() vip="" insec_registry="registry.local"
    local opt_short="m:w:"
    local opt_long="master:,worker:,vip:,insec_registry:,api_srv:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)     shift; master+=(${1}); shift;;
            -w | --worker)     shift; worker+=(${1}); shift;;
            --vip)             shift; vip=${1}; shift;;
            --api_srv)         shift; export API_SRV="${1}"; shift;;
            --insec_registry)  shift; insec_registry=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${vip}" ] && usage "vip master input"
    [ "$(array_size master)" -gt "0" ] || usage "at least one master"
    info_msg "Gen api-ha.yaml\n" && apilb_yaml > api-ha.yaml "${insec_registry}"
    info_msg "Gen api.conf\n" && gen_nginx_cfg ${master[*]} > api.conf
    info_msg "Gen haproxy.conf\n" && gen_haproxy_cfg ${master[*]} > haproxy.cfg
    for ip in ${master[*]}; do
        info_msg "Gen keepalived-${ip}.conf\n" && gen_keepalived_cfg 9999 ${vip} "eth0" ${ip} ${master[*]} > keepalived-${ip}.conf
    done
    NEWSRV=${API_SRV:-${vip}}
    [ -z "${API_SRV:-}" ] || {
    info_msg "# # execute on one master node\n"
    cat <<EOF
ssh root@${master[0]} kubectl -n kube-system get configmaps coredns -o yaml > coredns.cm.orig.yaml
cat << EO_YML | ssh root@${master[0]} kubectl replace -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        hosts {
           ${vip} ${API_SRV}
           fallthrough
        }
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
EO_YML
EOF
    }
    info_msg "# # execute on all nodes(masters \& workers), after replace coredns configmap\n"
    cat <<EOF
for ip in ${master[*]} ${worker[*]}; do
    ssh root@\${ip} bash -xs <<EO_SHELL
    sed -i "s/${NEWSRV}:6443/${NEWSRV}:60443/g" /etc/kubernetes/*.conf
    [ -e "/root/.kube/config" ] && sed -i "s/${NEWSRV}:6443/${NEWSRV}:60443/g" /root/.kube/config
$([ -z "${API_SRV:-}" ] || cat <<EO_DOC
    sed -i -e '/\s*${API_SRV}/d' /etc/hosts; echo '${vip} ${API_SRV}' >> /etc/hosts
EO_DOC
)
EO_SHELL
done
EOF
    cat <<EOF
for ip in ${master[*]}; do
    scp keepalived-\${ip}.conf root@\${ip}:/etc/kubernetes/keepalived.conf
done
for ip in ${master[*]}; do
    scp api.conf root@\${ip}:/etc/kubernetes/api.conf
done
for ip in ${master[*]}; do
    scp api-ha.yaml root@\${ip}:/etc/kubernetes/manifests/api-ha.yaml
done
EOF
    return 0
}
main "$@"
