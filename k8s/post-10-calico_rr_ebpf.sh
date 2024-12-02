#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2024-12-02T10:39:25+08:00]:post-10-calico_rr_ebpf.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
calico_bpf() {
    local api_srv=${1}
    echo "check requires ...., Calico > v3.13, kernel > 5.8(4.18)"
    kubectl get endpoints kubernetes -o wide
    command -v calicoctl &> /dev/null || { echo "***************calicoctl nofound"; return 1; }
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "install calico use tigera-operator, use this"
    local install_method=tigera-operator
    # echo "install calico use manifest, use this"
    # local install_method=kube-system
    IFS=':' read -r tname tport <<< "${api_srv}"
    cat <<EOF | kubectl apply -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: kubernetes-services-endpoint
  namespace: ${install_method}
data:
  KUBERNETES_SERVICE_HOST: '${tname}'
  KUBERNETES_SERVICE_PORT: '${tport}'
EOF
    # watch kubectl get pods -n calico-system
    sleep 30
    kubectl patch ds -n kube-system kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico": "true"}}}}}'
    # # If you cannot disable kube-proxy, do below
    # kubectl patch felixconfiguration.p default --patch='{"spec": {"bpfKubeProxyIptablesCleanupEnabled": false}}'
    kubectl get ds -n kube-system kube-proxy || true
    kubectl patch installation.operator.tigera.io default --type merge -p '{"spec":{"calicoNetwork":{"linuxDataplane":"BPF", "hostPorts":null}}}'
    calicoctl patch felixconfiguration default --patch='{"spec": {"bpfExternalServiceMode": "DSR"}}'
    echo "disable bpf"
cat << 'EOF'
    calicoctl patch felixconfiguration default --patch='{"spec": {"bpfExternalServiceMode": "Tunnel"}}'
    kubectl patch installation.operator.tigera.io default --type merge -p '{"spec":{"calicoNetwork":{"linuxDataplane":"Iptables"}}}'
    kubectl patch ds -n kube-system kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico": "null"}}}}}'
EOF
}

calico_route_reflector() {
    local asnumber=${1}
    local clusterid=${2}
    shift 2;
    local nodes=${*}
    local RR_LABEL=route-reflector
    echo "check requires ...."
    command -v calicoctl &> /dev/null || { echo "***************calicoctl nofound"; return 1; }
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl get nodes -o wide || true
    echo "Configure BGP Peering"
    calicoctl node status || true
    echo "Add RouteReflector to RouteReflector."
    cat <<EOF | calicoctl apply -f -
kind: BGPPeer
apiVersion: projectcalico.org/v3
metadata:
  name: rr-to-rr
spec:
  nodeSelector: has(${RR_LABEL})
  peerSelector: has(${RR_LABEL})
EOF
    echo "Add peer to RouteReflector."
    cat <<EOF | calicoctl apply -f -
kind: BGPPeer
apiVersion: projectcalico.org/v3
metadata:
  name: peer-to-rr
spec:
  nodeSelector: !has(${RR_LABEL})
  peerSelector: has(${RR_LABEL})
EOF
    for node in ${nodes}; do
        calicoctl patch node ${node} -p "{\"spec\": {\"bgp\": {\"routeReflectorClusterID\": \"${clusterid}\"}}}"
        kubectl label node ${node} ${RR_LABEL}=true --overwrite
    done
    echo "Disable node-to-node Mesh"
    calicoctl get bgpconfig default &>/dev/null || cat <<EOF | calicoctl create -f -
apiVersion: projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  nodeToNodeMeshEnabled: false
  asNumber: ${asnumber}
EOF
    calicoctl patch bgpconfiguration default -p '{"spec": {"nodeToNodeMeshEnabled": false}}'
}
usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
        -m | --master    *  <ip>    master ipaddr
        -r | --reflector *  <node>  reflector node name, multi input.
        --ebpf              <api:port>
                                    k8s cluster api-server-endpoint, like "<masterip>:6443"
                                    when ebpf mode,  service type NodePort not work,
                                                     service type Loadbalancer worked, so externalIP worked
                                     IPIP is not supported (Calico iptables does not support it either)
                                     VXLAN is the recommended overlay for eBPF mode.
        -U | --user         <user>  master ssh user, default root
        -P | --port         <int>   master ssh port, default 60022
        --asnumber          <int>   bgp as number, default 63401
        --clusterid         <ip>    master mulicast ipaddr default 224.0.0.222
        --sshpass           <str>   master ssh password, default use keyauth
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        exam:
    ${SCRIPTNAME} -m 172.16.0.150 -r telepresence1 -r telepresence2 -r telepresence3 --ebpf k8s.tsd.org:60443
# 关闭kube-proxy
kubectl patch ds -n kube-system kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico": "true"}}}}}'
# 开启eBPF DSR
calicoctl patch felixconfiguration default --patch='{"spec": {"bpfKubeProxyIptablesCleanupEnabled": false}}'
calicoctl patch felixconfiguration default --patch='{"spec": {"bpfEnabled": true}}'
calicoctl patch felixconfiguration default --patch='{"spec": {"bpfExternalServiceMode": "DSR"}}'

# 查看calico-bpf工具使用说明
kubectl exec -n calico-system ds/calico-node -- calico-node -bpf
# 查看eth0网卡计数器
kubectl exec -n calico-system ds/calico-node -- calico-node -bpf counters dump --iface=eth0
# 查看conntrack情况
kubectl exec -n calico-system ds/calico-node -- calico-node -bpf conntrack dump
# 查看路由表
kubectl exec -n calico-system ds/calico-node -- calico-node -bpf routes dump
|--------------------------------+---------------------------+----------|
| IP multicast address range     | Description               | Routable |
|--------------------------------+---------------------------+----------|
| 224.0.0.0 to 224.0.0.255       | Local subnetwork          | No       |
| 224.0.1.0 to 224.0.1.255       | Internetwork control      | Yes      |
| 224.0.2.0 to 224.0.255.255     | AD-HOC block              | Yes      |
| 224.1.0.0 to 224.1.255.255     | Reserved                  |          |
| 224.2.0.0 to 224.2.255.255     | SDP/SAP block             | Yes      |
| 224.3.0.0 to 224.4.255.255     | AD-HOC block              | Yes      |
| 225.0.0.0 to 231.255.255.255   | Reserved                  |          |
| 232.0.0.0 to 232.255.255.255   | Source-specific multicast | Yes      |
| 233.0.0.0 to 233.251.255.255   | GLOP addressing           | Yes      |
| 233.252.0.0 to 233.255.255.255 | AD-HOC block 3            | Yes      |
| 234.0.0.0 to 234.255.255.255   | Unicast-prefix-based      | Yes      |
| 235.0.0.0 to 238.255.255.255   | Reserved                  |          |
| 239.0.0.0 to 239.255.255.255   | Administratively scoped   | Yes      |
|--------------------------------+---------------------------+----------|
EOF
)"; echo -e "${usage_doc}"
    exit 1
}
main() {
    local master="" reflector=() user="root" port=60022 asnumber=63401 clusterid=224.0.0.222 ebpf=""
    local opt_short="m:r:U:P:"
    local opt_long="master:,reflector:,ebpf:,user:,port:,asnumber:,clusterid:,sshpass:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)    shift; master=${1}; shift;;
            -r | --reflector) shift; reflector+=("${1}"); shift;;
            --ebpf)           shift; ebpf=${1}; shift;;
            -U | --user)      shift; user=${1}; shift;;
            -P | --port)      shift; port=${1}; shift;;
            --asnumber)       shift; asnumber=${1}; shift;;
            --clusterid)      shift; clusterid=${1}; shift;;
            --sshpass)        shift; set_sshpass "${1}"; shift;;
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
    [ -z "${master}" ] && usage "master must input"
    [ "$(array_size reflector)" -gt "0" ] || usage "reflector must input"
    info_msg "choose some nodes as reflector nodes\n"
    ssh_func "${user}@${master}" "${port}" calico_route_reflector "${asnumber}" "${clusterid}" ${reflector[@]}
    [ -z "${ebpf}" ] || {
        info_msg "use EBPF & DSR\n"
        ssh_func "${user}@${master}" "${port}" calico_bpf "${ebpf}"
    }
    # # modify asnumber
    # calicoctl patch bgpconfiguration default -p '{"spec": {"asNumber": "64513"}}'
    info_msg "on non reflector node run: calicoctl node status\n"
    # for ip in $(ip r | grep bird | awk '{ print $1 }' | grep -v blackhole ); do ping -W1 -c1 ${ip%/*} &>/dev/null && echo "${ip} OK" || echo "${ip} ERR"; done
    info_msg "diag: kubectl exec -n calico-system calico-node-abcdef -- calico-node -bpf help\n"
    info_msg "diag: kubectl exec -n calico-system calico-node-abcdef -- calico-node -bpf conntrack dump\n"
    info_msg "diag: kubectl get felixconfiguration -o yaml\n"
    info_msg "undo: kubectl delete -n tigera-operator servicemap kubernetes-services-endpoint\n"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
