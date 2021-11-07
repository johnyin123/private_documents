#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("new_k8s.sh - fc170a5 - 2021-11-06T12:21:07+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
:<<EOF
## https://www.cni.dev/plugins/current/main/bridge/
name (string, required): the name of the network.
type (string, required): “bridge”.
bridge (string, optional): name of the bridge to use/create. Defaults to “cni0”.
isGateway (boolean, optional): assign an IP address to the bridge. Defaults to false.
isDefaultGateway (boolean, optional): Sets isGateway to true and makes the assigned IP the default route. Defaults to false.
forceAddress (boolean, optional): Indicates if a new IP address should be set if the previous value has been changed. Defaults to false.
ipMasq (boolean, optional): set up IP Masquerade on the host for traffic originating from this network and destined outside of it. Defaults to false.
mtu (integer, optional): explicitly set MTU to the specified value. Defaults to the value chosen by the kernel.
hairpinMode (boolean, optional): set hairpin mode for interfaces on the bridge. Defaults to false.
ipam (dictionary, required): IPAM configuration to be used for this network. For L2-only network, create empty dictionary.
promiscMode (boolean, optional): set promiscuous mode on the bridge. Defaults to false.
vlan (int, optional): assign VLAN tag. Defaults to none.
EOF
init_bridge_cni() {
    local bridge=${1}
    local subnet=${2}
    local gw=${3}
    local masq=${4}
    shift 4
    local routes=("$@")
    mkdir -p /etc/cni/net.d
    local tip="" tmask=""
    IFS='/' read -r tip tmask <<< "${subnet}"
    # { "dst": "1.1.1.1/32", "gw":"10.15.30.1"}
    cat <<EOF | tee /etc/cni/net.d/10-${bridge}.conf
{
  "cniVersion": "0.3.1",
  "name": "mynet",
  "type": "bridge",
  "bridge": "${bridge}",
  "isDefaultGateway": false,
  "isGateway": false,
  "ipMasq": ${masq},
  "ipam": {
    "type": "host-local",
    "subnet": "${subnet}",
    "gateway": "${gw}",
    "routes": [
      { "dst": "0.0.0.0/0" }
    ]
  }
}
EOF
    [ -e /sys/class/net/${bridge}/bridge/bridge_id ] || {
        cat <<EOF | tee /etc/network/interfaces.d/${bridge}
auto ${bridge}
iface ${bridge} inet static
    bridge_ports none
    $(
    [ "${masq}" = true ] && echo "address ${gw}/${tmask}"
    for i in "$@"; do
        IFS=',' read -r x y <<< "${i}"
        echo "    post-up (/usr/sbin/ip route add $x via $y || true)"
    done
    )
EOF
    }
    ifup ${bridge}
    ip address show dev ${bridge}
    # # check cni ok
    # rand=${RANDOM}
    # testns=ns${rand}
    # ip netns add ${testns}
    # CNI_COMMAND=ADD CNI_CONTAINERID=${rand} CNI_NETNS=/var/run/netns/${testns} CNI_IFNAME=veth${rand} CNI_PATH=/opt/cni/bin/ /opt/cni/bin/bridge < /etc/cni/net.d/10-${bridge}.conf
    # ip netns exec ns_a /bin/bash -c "ping -c 3 $(cat /etc/cni/net.d/10-mynet.conf | jq .ipam.gateway)"
    # ip netns del ${testns}
}

pre_conf_k8s_host() {
    # ${HOSTNAME:-$(hostname)}
    echo "127.0.0.1       localhost" > /etc/hosts
    swapoff -a
    sed -iE "/\sswap\s/d" /etc/fstab
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
    modprobe br_netfilter
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
    sysctl --system
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "http://hub-mirror.c.163.com"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "data-root": "/var/lib/docker",
  "storage-driver": "overlay2",
  "iptables": false,
  "bridge": "none"
}
EOF
    systemctl restart docker
}

gen_k8s_join_cmds() {
    #kubeadm token list -o json
    local token=$(kubeadm token create)
    # kubeadm token create --print-join-command
    local sha_hash=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    # reupload certs
    # kubeadm init phase upload-certs --upload-certs
    local certs=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
    local api_srv=$(sed -n "s/\s*server:\s*\(.*\)/\1/p" /etc/kubernetes/kubelet.conf)
    cat <<EOF
kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash} --control-plane --certificate-key ${certs}
kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash}
EOF
}

init_k8s_dashboard() {
    # 部署dashboard（在master上操作）
    kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta1/aio/deploy/recommended.yaml
    kubectl get pods --namespace=kubernetes-dashboard
    # 修改service配置，将type: ClusterIP改成NodePort
    # kubectl edit service kubernetes-dashboard --namespace=kubernetes-dashboard
    kubectl get service kubernetes-dashboard --namespace=kubernetes-dashboard -o yaml | \
    sed 's/type:\s*[^\s]*/type: NodePort/g' | \
    kubectl apply -f -
    kubectl get service --namespace=kubernetes-dashboard
    kubectl create serviceaccount dashboard-admin -n kube-system
    kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
    kubectl describe secrets -n kube-system $(kubectl -n kube-system get secret | awk '/dashboard-admin/{print $1}')
}

modify_kube_proxy_ipvs() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl -n kube-system get configmaps kube-proxy -o yaml | \
    sed 's/mode:\s*"[^"]*"/mode: "ipvs"/g' | \
    kubectl apply -f -
    # kubectl -n kube-system edit configmaps kube-proxy -o yaml
    # kube-proxy ConfigMap, [mode=""] changed to [ipvs]
    kubectl -n kube-system delete pod -l k8s-app=kube-proxy
    # kubectl -n kube-system logs  kube-proxy-tknk8
}

init_first_k8s_master() {
    local api_srv=${1} # apiserver dns-name:port
    # 初始kubeadm集群环境（仅master节点）
    kubeadm config images list
    kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version=$(kubelet --version | awk '{ print $2}')
    kubeadm init --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version=$(kubelet --version | awk '{ print $2}') --control-plane-endpoint "${api_srv}" --upload-certs
    # # reupload certs
    # kubeadm init phase upload-certs --upload-certs
    #--apiserver-advertise-address=<ip-address-of-master-vm> #--service-cidr=10.1.0.0/16 --pod-network-cidr=172.16.0.0/16 
    # --control-plane-endpoint to set the shared endpoint for all control-plane nodes. Such an endpoint can be either a DNS name or an IP address of a load-balancer.
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" > /etc/profile.d/k8s.conf
    chmod 644 /etc/profile.d/k8s.conf
    # # 使Master Node参与工作负载
    # kubectl taint nodes --all node-role.kubernetes.io/master-
    # # 禁止master部署pod</p> 
    # kubectl taint nodes k8s node-role.kubernetes.io/master=true:NoSchedule
    # Pending check
    # kubectl -n kube-system describe pod coredns-7f6cbbb7b8-7phlt
    # kubectl describe node md1
    # kubectl get pods --all-namespaces
    # kubectl -n kube-system edit configmaps coredns -o yaml
    # kubectl -n kube-system delete pod coredns-7f6cbbb7b8-lfvxb
    # kubectl -n kube-system logs coredns-7f6cbbb7b8-vkj2l
    # kubectl exec -it etcd-k8s-master sh
    kubectl -n kube-system get pod    #看到所有的pod都处于running状态。
    kubectl get nodes
    kubeadm token list
    # kubectl delete nodes md2
    kubectl -n kube-system describe pod | grep IP
}

add_k8s_master() {
    local api_srv=${1}
    local token=${2}
    local sha_hash=${3}
    local certs=${4}
    kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash} --control-plane --certificate-key ${certs}
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" > /etc/profile.d/k8s.conf
    chmod 644 /etc/profile.d/k8s.conf
}

add_k8s_worker() {
    local api_srv=${1}
    local token=${2}
    local sha_hash=${3}
    kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash}
    #kubectl -n kube-system get cm kubeadm-config -o yaml
}

teardown() {
    local name=${HOSTNAME:-$(hostname)}
    # 在Master节点上运行：
    kubectl drain ${name} --delete-local-data --force --ignore-daemonsets || true
    kubectl delete node ${name} || true
    for b in $(jq -r .bridge /etc/cni/net.d/*); do
        ifdown ${b} || true
        rm -f /etc/network/interfaces.d/${b} || true
    done
    # 移除的节点上，重置kubeadm的安装状态：
    kubeadm reset -f || true
    rm -fr /etc/cni/net.d/* || true
}
# remote execute function end!
################################################################################
SSH_PORT=${SSH_PORT:-60022}

remove_k8s_cfg() {
    local ipaddr=${1}
    info_msg "${ipaddr} teardown all ceph config!\n"
    ssh_func "root@${ipaddr}" ${SSH_PORT} "teardown"
}

init_kube_bridge_cni() {
    local bridge=${1}
    local masq=${2}
    local nodes=${3}
    local ipaddr="" subnet="" gw="" route_gw="" route_subnet="" routes=()
    for ipaddr in $(array_print_label ${nodes}); do
        routes=()
        subnet="$(array_get ${nodes} "${ipaddr}")"
        gw="${subnet%.*}.1"
        for route_gw in $(array_print_label ${nodes}); do
            [ "${route_gw}" = "${ipaddr}" ] || {
                routes+=("$(array_get ${nodes} ${route_gw}),${route_gw}")
            }
        done
        vinfo_msg <<EOF
"****** ${ipaddr} init bridge(${bridge}) cni.
  sbunet=${subnet}
  gateway=${gw}
  MASQ=${masq}
  routes=${routes[@]}
EOF
        ssh_func "root@${ipaddr}" ${SSH_PORT} pre_conf_k8s_host
        ssh_func "root@${ipaddr}" ${SSH_PORT} init_bridge_cni "${bridge}" "${subnet}" "${gw}" "${masq}" "${routes[@]}"
    done
}

init_kube_cluster() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local api_srv=${3}
    [ "$(array_size master)" -gt "0" ] || return 1
    local ipaddr=$(array_get master 0)
    info_msg "****** ${ipaddr} init first master(${api_srv})\n"
    IFS=':' read -r tname tport <<< "${api_srv}"
    local hosts="${ipaddr} ${tname}"
    ssh_func "root@${ipaddr}" ${SSH_PORT} "echo ${hosts} >> /etc/hosts"
    ssh_func "root@${ipaddr}" ${SSH_PORT} init_first_k8s_master "${api_srv}"
    ssh_func "root@${ipaddr}" ${SSH_PORT} modify_kube_proxy_ipvs
    ssh_func "root@${ipaddr}" ${SSH_PORT} init_k8s_dashboard
    #kubeadm token list -o json
    local token=$(ssh_func "root@${ipaddr}" ${SSH_PORT} "kubeadm token create")
    # kubeadm token create --print-join-command
    local sha_hash=$(ssh_func "root@${ipaddr}" ${SSH_PORT} "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")
    # reupload certs
    # kubeadm init phase upload-certs --upload-certs
    local certs=$(ssh_func "root@${ipaddr}" ${SSH_PORT} "kubeadm init phase upload-certs --upload-certs | tail -n 1")
    for ((i=1;i<$(array_size master);i++)); do
        ipaddr=$(array_get master ${i})
        info1_msg "****** ${ipaddr} add master(${api_srv})\n"
        ssh_func "root@${ipaddr}" ${SSH_PORT} "echo ${hosts} >> /etc/hosts"
        ssh_func "root@${ipaddr}" ${SSH_PORT} add_k8s_master "${api_srv}" "${token}" "${sha_hash}" "${certs}"
    done
    for ipaddr in $(array_print worker); do
        info2_msg "****** ${ipaddr} add worker(${api_srv})\n"
        ssh_func "root@${ipaddr}" ${SSH_PORT} "echo ${hosts} >> /etc/hosts"
        ssh_func "root@${ipaddr}" ${SSH_PORT} add_k8s_worker "${api_srv}" "${token}" "${sha_hash}"
    done
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        --apiserver  <str>  k8s cluster api-server-endpoint
                            default "k8sapi.local.com:6443"
                            k8sapi.local.com is first master node, store in /etc/hosts(all masters&workers)
                            u should make a loadbalance to all masters later,
        -m|--master  <ip> * master nodes
        -w|--worker  <ip>   worker nodes 
        -b|--bridge  <str>  k8s bridge, default "cn0"
        --teardown   <ip>   remove all ceph config
        --password   <str>  ssh password(default use sshkey)
        --gen_join_cmds     only generate join commands
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    Example:
        MASQ=false, the gateway is outside, else gateway is bridge(cn0)
        Debian install docker:
            apt -y install wget curl apt-transport-https ca-certificates ethtool socat bridge-utils gnupg
            wget -q -O- 'https://mirrors.aliyun.com/docker-ce/linux/debian/gpg' | apt-key add -
            echo "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/debian \$(sed -n "s/^\s*VERSION_CODENAME\s*=\s*\(.*\)/\1/p" /etc/os-release) stable" > /etc/apt/sources.list.d/docker.list
            apt update && apt -y install docker-ce
        Debian install k8s:
            wget -q -O- https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
            echo "deb https://mirrors.aliyun.com/kubernetes/apt kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
            apt update && apt -y install kubelet kubectl kubeadm
EOF
    exit 1
}

main() {
    local password="" master=() worker=() teardown=() bridge="cni0" apiserver="k8sapi.local.com:6443" gen_join_cmds=""
    local opt_short="m:w:b:"
    local opt_long="password:,gen_join_cmds,apiserver:,master:,worker:,bridge:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --apiserver)    shift; apiserver=${1}; shift;;
            --gen_join_cmds)shift; gen_join_cmds=1;; 
            -m | --master)  shift; master+=(${1}); shift;;
            -w | --worker)  shift; worker+=(${1}); shift;;
            -b | --bridge)  shift; bridge=${1}; shift;;
            --teardown)     shift; teardown+=(${1}); shift;;
            --password)     shift; password="${1}"; shift;;
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
    [ -z ${password} ]  || set_sshpass "${password}"
    local ipaddr="" i=0 PREFIX=172.16
    for ipaddr in "${teardown[@]}"; do
        remove_k8s_cfg ${ipaddr}
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    [ "$(array_size master)" -gt "0" ] || usage "at least one master"
    [ -z "${gen_join_cmds}" ] || {
        ssh_func "root@${master[0]}" ${SSH_PORT} gen_k8s_join_cmds 2>/dev/null
        info_msg "GEN_CMDS OK\n"
        return 0
    }
    declare -A srv_net_map=()
    for ipaddr in ${master[@]} ${worker[@]}; do
        srv_net_map[$ipaddr]="${PREFIX}.$i.0/22"
        let i+=4
    done
    # print_kv srv_net_map
    local masq=true
    init_kube_bridge_cni "${bridge}" "${masq}" srv_net_map "${apiserver}"
    init_kube_cluster master worker "${apiserver}"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
