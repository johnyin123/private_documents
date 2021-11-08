#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("new_k8s.sh - f5004dd - 2021-11-08T12:31:18+08:00")
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

pre_get_gcr_images() {
    local mirror="${1}"
    local mirror_img="${2}"
    local gcr_img="${3}"
    #kubeadm config images list | sed "s|k8s.gcr.io\(.*\)|\1|g" | awk  -v mirror=${mirror} '{printf "docker pull %s%s\n", mirror, $1; printf "docker tag %s%s k8s.gcr.io%s\n", mirror, $1, $1; printf "docker rmi %s%s\n", mirror, $1}' | bash -x
    # # 下载被墙的镜像 registry.aliyuncs.com/google_containers
    docker pull "${mirror}/${mirror_img}"
    docker tag  "${mirror}/${mirror_img}" "k8s.gcr.io/${gcr_img}"
    docker rmi  "${mirror}/${mirror_img}"
}

pre_conf_k8s_host() {
    echo "127.0.0.1       localhost ${HOSTNAME:-$(hostname)}" > /etc/hosts
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
    # Docker中国区官方镜像
    # https://registry.docker-cn.com
    # 网易
    # http://hub-mirror.c.163.com
    # ustc
    # https://docker.mirrors.ustc.edu.cn
    # 阿里云容器  服务
    # https://cr.console.aliyun.com/
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

init_k8s_ingress() {
    # # Support Versions table
    # https://github.com/kubernetes/ingress-nginx
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.0.4/deploy/static/provider/cloud/deploy.yaml
    kubectl get pods -n ingress-nginx -o wide
    # 通过创建的svc可以看到已经把ingress-nginx service在主机映射的端口为31199(http)，32759(https)
    kubectl get svc -n ingress-nginx

}

init_k8s_dashboard() {
    # 部署dashboard（在master上操作）
    kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta1/aio/deploy/recommended.yaml
    kubectl get pods --namespace=kubernetes-dashboard
    # 修改service配置，将type: ClusterIP改成NodePort
    # kubectl edit service kubernetes-dashboard --namespace=kubernetes-dashboard
    kubectl get service kubernetes-dashboard --namespace=kubernetes-dashboard -o yaml | \
    sed 's/type:\s*[^ ]*$/type: NodePort/g' | \
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
    # kubeadm config images list
    # kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version=$(kubelet --version | awk '{ print $2}')
    # kubeadm init --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version=$(kubelet --version | awk '{ print $2}') --control-plane-endpoint "${api_srv}" --upload-certs
    kubeadm init --kubernetes-version=$(kubelet --version | awk '{ print $2}') --control-plane-endpoint "${api_srv}" --upload-certs
    echo "FIX 'kubectl get cs' Unhealthy"
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-controller-manager.yaml
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-scheduler.yaml

    # # reupload certs
    # kubeadm init phase upload-certs --upload-certs
    #--apiserver-advertise-address=<ip-address-of-master-vm> #--service-cidr=10.1.0.0/16 --pod-network-cidr=172.16.0.0/16 
    # --control-plane-endpoint to set the shared endpoint for all control-plane nodes. Such an endpoint can be either a DNS name or an IP address of a load-balancer.
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" > /etc/profile.d/k8s.sh
    chmod 644 /etc/profile.d/k8s.sh
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
    echo "certificate expiration date"
    openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text |grep ' Not '
}

add_k8s_master() {
    local api_srv=${1}
    local token=${2}
    local sha_hash=${3}
    local certs=${4}
    kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash} --control-plane --certificate-key ${certs}
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" > /etc/profile.d/k8s.sh
    chmod 644 /etc/profile.d/k8s.sh
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

download() {
    local ipaddr=${1}
    local port=${2}
    local user=${3}
    local rfile=${4}
    local lfile=${5}
    warn_msg "download ${user}@${ipaddr}:${port}${rfile} ====> ${lfile}\n"
    try scp -P${port} ${user}@${ipaddr}:${rfile} ${lfile}
}

upload() {
    local lfile=${1}
    local ipaddr=${2}
    local port=${3}
    local user=${4}
    local rfile=${5}
    warn_msg "upload ${lfile} ====> ${user}@${ipaddr}:${port}${rfile}\n"
    try scp -P${port} ${lfile} ${user}@${ipaddr}:${rfile}
}


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

prepare_kube_images() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local ipaddr="" img="" imgid=""
    local mirror="registry.aliyuncs.com/google_containers"
    # [mirror-img]=gcr-img
    declare -A img_map=(
        [kube-apiserver:v1.22.3]=kube-apiserver:v1.22.3
        [kube-controller-manager:v1.22.3]=kube-controller-manager:v1.22.3
        [kube-scheduler:v1.22.3]=kube-scheduler:v1.22.3
        [kube-proxy:v1.22.3]=kube-proxy:v1.22.3
        [pause:3.5]=pause:3.5
        [etcd:3.5.0-0]=etcd:3.5.0-0
        [coredns:v1.8.4]=coredns/coredns:v1.8.4
    )
    #kubeadm config images list | sed "s|k8s.gcr.io\(.*\)|\1|g" | awk  -v mirror=${mirror} '{printf "docker pull %s%s\n", mirror, $1; printf "docker tag %s%s k8s.gcr.io%s\n", mirror, $1, $1; printf "docker rmi %s%s\n", mirror, $1}' | bash -x
    for ipaddr in $(array_print worker) $(array_print master); do
        for img in $(array_print_label img_map); do
            [ -z "$(ssh_func "root@${ipaddr}" ${SSH_PORT} "docker image ls -q k8s.gcr.io/$(array_get img_map ${img})")" ] || continue
            file_exists "${DIRNAME}/${img}.tar.gz" && {
                info_msg "Import kcr image for ${ipaddr}(${img})\n"
                upload "${DIRNAME}/${img}.tar.gz" ${ipaddr} ${SSH_PORT} "root" "/tmp/${img}.tar.gz"
                ssh_func "root@${ipaddr}" ${SSH_PORT} "gunzip -c /tmp/${img}.tar.gz | docker import - k8s.gcr.io/$(array_get img_map ${img})"
                ssh_func "root@${ipaddr}" ${SSH_PORT} "rm -f /tmp/${img}.tar.gz"
                continue
            }
            info_msg "Prepare kcr image for ${ipaddr}(${img})\n"
            ssh_func "root@${ipaddr}" ${SSH_PORT} pre_get_gcr_images "${mirror}" "${img}" "$(array_get img_map ${img})"
            imgid=$(ssh_func "root@${ipaddr}" ${SSH_PORT} "docker image ls -q k8s.gcr.io/$(array_get img_map ${img})")
            ssh_func "root@${ipaddr}" ${SSH_PORT} "docker save ${imgid} | gzip > /tmp/${img}.tar.gz"
            download ${ipaddr} ${SSH_PORT} "root" "/tmp/${img}.tar.gz" "${DIRNAME}/${img}.tar.gz"
            ssh_func "root@${ipaddr}" ${SSH_PORT} "rm -f /tmp/${img}.tar.gz"
        done
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
        -b|--bridge  <str>  k8s bridge_cni, bridge name
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
    local password="" master=() worker=() teardown=() bridge="" apiserver="k8sapi.local.com:6443" gen_join_cmds=""
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
    local ipaddr=""
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
    prepare_kube_images master worker
    [ -z "${bridge}" ] || {
        info_msg "install bridge_cni begin(${bridge})\n"
        declare -A srv_net_map=()
        local i=0 PREFIX=172.16 masq=true
        for ipaddr in ${master[@]} ${worker[@]}; do
            srv_net_map[$ipaddr]="${PREFIX}.$i.0/22"
            let i+=4
        done
        init_kube_bridge_cni "${bridge}" "${masq}" srv_net_map "${apiserver}"
        info_msg " install bridge_cni end(${bridge})"
    }
    init_kube_cluster master worker "${apiserver}"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
