#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2024-11-18T08:45:44+08:00]:calico_rr_ebpf.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
calico_bpf() {
    local api_srv=${1}
    echo "check requires ...."
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
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -m | --master    *  <ip>    master ipaddr
        -r | --reflector *  <node>  reflector node name, multi input.
        --ebpf              <api:port>
                                    k8s cluster api-server-endpoint, like "k8sapi.local.com:6443"
                                    default no use ebpf, this script ebpf not work now
        -U | --user         <user>  master ssh user, default root
        -P | --port         <int>   master ssh port, default 60022
        --asnumber          <int>   bgp as number, default 63401
        --clusterid         <ip>    master mulicast ipaddr default 224.0.0.1
        --sshpass           <str>   master ssh password, default use keyauth
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local master="" reflector=() user="root" port=60022 asnumber=63401 clusterid=224.0.0.1 ebpf=""
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
