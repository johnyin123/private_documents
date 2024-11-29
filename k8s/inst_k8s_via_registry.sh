#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("fab271e[2024-11-28T16:43:02+08:00]:inst_k8s_via_registry.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
CALICO_YML="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml"
CALICO_CUST_YML="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml"
L_CALICO_YML="tigera-operator.yaml"
R_CALICO_YML="$(mktemp)"
L_CALICO_CUST_YML="custom-resources.yaml"
R_CALICO_CUST_YML="$(mktemp)"

init_calico_cni() {
    local svc_cidr=${1}
    local pod_cidr=${2}
    local calico_yml=${3}
    local calico_cust_yml=${4}
    local insec_registry=${5}
    local crossnet_method=${6}
    [ -e "${calico_yml}" ] || [ -e "${calico_cust_yml}" ] || return 1
    # sed -i "s|replicas\s*:.*|replicas: ${TYPHA_REPLICAS:-1}|g" "${calico_typha_yml}"
    sed -i "s|cidr\s*:.*|cidr: ${pod_cidr}|g" "${calico_cust_yml}"
    # # IPIPCrossSubnet,IPIP,VXLAN,VXLANCrossSubnet,None
    sed -i "s|encapsulation\s*:.*|encapsulation: ${crossnet_method}|g" "${calico_cust_yml}"
    # # modify registry
    [ -z "${insec_registry}" ] || {
        sed -i "s|spec\s*:\s*$|spec:\n  registry: ${insec_registry}|g" "${calico_cust_yml}"
        sed -i "s|image\s*:.*operator|image: ${insec_registry}/tigera/operator|g" "${calico_yml}"
    }
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl create -f "${calico_yml}" # need wait a moment, avoid cust yml error
    kubectl get nodes -o wide || true
    kubectl get pods --all-namespaces -o wide || true
    kubectl create -f "${calico_cust_yml}"
    calicoctl node status || true
    rm -f "${calico_yml}" "${calico_cust_yml}" || true
}
pre_conf_k8s_host() {
    local master=${1}
    local apiserver=${2}
    local nameserver=${3}
    local insec_registry=${4}
    IFS=':' read -r tname tport <<< "${apiserver}"
    touch /etc/hosts || true
    sed -i -E "/\s*\slocalhost\s*/d" /etc/hosts
    echo "127.0.0.1 localhost ${HOSTNAME:-$(hostname)}" >> /etc/hosts
    # skip ip address
    ip route get "${tname:-127.0.0.1}" &>/dev/null || {
        sed -i -E "/\s*\s${tname}\s*/d" /etc/hosts
        echo "${master} ${tname}" >> /etc/hosts
    }
    [ -z "${nameserver}" ] || echo "nameserver ${nameserver}" > /etc/resolv.conf
    touch /etc/resolv.conf || true
    # for external etcd
    mkdir -p /etc/kubernetes/pki/etcd/ || true
    swapoff -a
    sed -i "/\s*swap\s/d" /etc/fstab
    echo "br_netfilter" >/etc/modules-load.d/k8s.conf
    modprobe br_netfilter
    sed --quiet -i -E \
        -e '/(net.ipv4.ip_forward|net.bridge.bridge-nf-call-ip6tables|net.bridge.bridge-nf-call-iptables).*/!p' \
        /etc/sysctl.conf
    cat <<EOF | tee /etc/sysctl.d/99-zz-k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.netfilter.nf_conntrack_max = 1000000
EOF
    sysctl --system &>/dev/null
    local k8s_version=$(kubelet --version | awk '{ print $2}')
    echo "****K8s VERSION: ${k8s_version}"
    local pausekey=$(kubeadm config images list ${insec_registry:+--image-repository ${insec_registry}/google_containers} --kubernetes-version=${k8s_version} 2>/dev/null | grep pause)
    echo "****PAUSE: ${pausekey}"
    # change sandbox_image on all nodes
    mkdir -vp /etc/containerd && containerd config default > /etc/containerd/config.toml || true
    sed -i -e "s|sandbox_image\s*=.*|sandbox_image = \"${pausekey}\"|g" /etc/containerd/config.toml
    sed -i 's/SystemdCgroup\s*=.*$/SystemdCgroup = true/g' /etc/containerd/config.toml
    [ -z "${insec_registry}" ] || sed -i -E "s|(^\s*)\[(plugins.*registry.mirrors)\]$|\1[\2]\n\1  [\2.\"${insec_registry}\"]\n\1    endpoint = [\"http://${insec_registry}\"]|g" /etc/containerd/config.toml
    systemctl daemon-reload || true
    systemctl restart containerd.service || true
    systemctl enable containerd.service || true
    systemctl enable kubelet.service
    systemctl disable firewalld --now || true
}

modify_kube_proxy_ipvs() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl -n kube-system get configmaps kube-proxy -o yaml | \
    sed 's/mode:\s*"[^"]*"/mode: "ipvs"/g' | \
    kubectl apply -f -
    kubectl -n kube-system delete pod -l k8s-app=kube-proxy
}
init_first_k8s_master_use_extern_etcd() {
    local apiserver=${1} # apiserver dns-name:port
    local skip_proxy=${2}
    local pod_cidr=${3}
    local svc_cidr=${4}
    local insec_registry=${5}
    shift 5;
    local etcd="${*}"
    local opts="--upload-certs"
    kubeadm config print init-defaults --kubeconfig ClusterConfiguration | sed -n '1,/^---/!p' | sed -n '/local:/,/dataDir:/!p' > /tmp/kubeadm-config.yaml
    ${skip_proxy} && opts="--skip-phases=addon/kube-proxy ${opts}"
    [ -z "${API_VIP:-}" ] || opts="--apiserver-cert-extra-sans=${API_VIP} ${opts}"
    [ -z "${apiserver}" ] || sed -i "s|controllerManager:.*|controlPlaneEndpoint: ${apiserver}|g" /tmp/kubeadm-config.yaml
    [ -z "${pod_cidr}" ] || sed -i "s|networking:|networking:\n  podSubnet: ${pod_cidr}|g" /tmp/kubeadm-config.yaml
    [ -z "${svc_cidr}" ] || sed -i "s|networking:|networking:\n  serviceSubnet: ${svc_cidr}|g" /tmp/kubeadm-config.yaml
    [ -z "${insec_registry}" ] || sed -i "s|imageRepository:.*|imageRepository: ${insec_registry}/google_containers|g" /tmp/kubeadm-config.yaml
    echo "add external etcd"
    sed -i "s|etcd:|etcd:\n  external:\n    endpoints:|g" /tmp/kubeadm-config.yaml
    sed -i "s|external:|external:\n    caFile: /etc/kubernetes/pki/etcd/ca.pem|g" /tmp/kubeadm-config.yaml
    sed -i "s|external:|external:\n    certFile: /etc/kubernetes/pki/etcd/etcd.pem|g" /tmp/kubeadm-config.yaml
    sed -i "s|external:|external:\n    keyFile: /etc/kubernetes/pki/etcd/etcd.key|g" /tmp/kubeadm-config.yaml
    for it in ${etcd}; do
        sed -i "s|endpoints:|endpoints:\n    - ${it}|g" /tmp/kubeadm-config.yaml
    done
    local k8s_version=$(kubelet --version | awk '{ print $2}')
    sed -i "s/kubernetesVersion:.*/kubernetesVersion: ${k8s_version}/g" /tmp/kubeadm-config.yaml
    kubeadm init --config /tmp/kubeadm-config.yaml ${opts}
    echo "FIX 'kubectl get cs' Unhealthy"
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-controller-manager.yaml
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-scheduler.yaml
    mkdir -p ~/.kube && cat /etc/kubernetes/admin.conf > ~/.kube/config
    echo "source <(kubectl completion bash)" > /etc/profile.d/k8s.sh
    chmod 644 /etc/profile.d/k8s.sh
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl cluster-info || true
}
init_first_k8s_master() {
    local apiserver=${1} # apiserver dns-name:port
    local skip_proxy=${2}
    local pod_cidr=${3}
    local svc_cidr=${4}
    local insec_registry=${5}
    local opts="${apiserver:+--control-plane-endpoint ${apiserver}} --upload-certs ${pod_cidr:+--pod-network-cidr=${pod_cidr}} ${svc_cidr:+--service-cidr ${svc_cidr}} --apiserver-advertise-address=0.0.0.0 ${insec_registry:+--image-repository=${insec_registry}/google_containers}"
    ${skip_proxy} && opts="--skip-phases=addon/kube-proxy ${opts}"
    [ -z "${API_VIP:-}" ] || opts="--apiserver-cert-extra-sans=${API_VIP} ${opts}"
    local k8s_version=$(kubelet --version | awk '{ print $2}')
    kubeadm init --kubernetes-version ${k8s_version} ${opts}
    echo "FIX 'kubectl get cs' Unhealthy"
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-controller-manager.yaml
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-scheduler.yaml
    mkdir -p ~/.kube && cat /etc/kubernetes/admin.conf > ~/.kube/config
    echo "source <(kubectl completion bash)" > /etc/profile.d/k8s.sh
    chmod 644 /etc/profile.d/k8s.sh
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl cluster-info || true
}
enbale_pod_scheduling_on_master() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl taint nodes --all node-role.kubernetes.io/master-
}
add_k8s_master() {
    local apiserver=${1}
    local token=${2}
    local sha_hash=${3}
    local certs=${4}
    kubeadm join ${apiserver} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash} --control-plane --certificate-key ${certs}
    mkdir -p ~/.kube && cat /etc/kubernetes/admin.conf > ~/.kube/config
    echo "source <(kubectl completion bash)" > /etc/profile.d/k8s.sh
    chmod 644 /etc/profile.d/k8s.sh
}

add_k8s_worker() {
    local apiserver=${1}
    local token=${2}
    local sha_hash=${3}
    kubeadm join ${apiserver} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash}
    #kubectl -n kube-system get cm kubeadm-config -o yaml
}

teardown() {
    local name=${HOSTNAME:-$(hostname)}
    # 在Master节点上运行：
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl drain ${name} --delete-emptydir-data --force --ignore-daemonsets &>/dev/null || true
    kubectl delete node ${name} &>/dev/null || true
    for b in $(jq -r .bridge /etc/cni/net.d/* 2>/dev/null); do
        ifdown ${b} 2>/dev/null || true
        rm -f /etc/network/interfaces.d/${b} || true
        rm -f /etc/sysconfig/network-scripts/ifcfg-${b} || true
    done
    # 移除的节点上，重置kubeadm的安装状态：
    kubeadm reset -f &>/dev/null || true
    rm -fr ~/.kube /etc/cni/net.d/* /etc/profile.d/k8s.sh || true
    # # # remove calico
    # kubectl delete -f calico.yaml
    modprobe -r ipip || true
    rm -rf /var/lib/cni/ || true
    rm -rf /etc/cni/net.d/* || true
    # systemctl restart kubelet
}
# remote execute function end!
################################################################################
prepare_yml() {
    local user=${1}
    local port=${2}
    local ipaddr=${3}
    local local_yml=${4}
    local remote_yml=${5}
    local yml_url=${4}
    [ -e "${local_yml}" ] && {
        upload "${local_yml}" "${ipaddr}" "${port}" "${user}" "${remote_yml}"
    } || {
        warn_msg "Local yaml ${local_yml} NOT EXIST!!, remote download it.\n"
        ssh_func "${user}@${ipaddr}" "${port}" "wget -q ${yml_url} -O ${remote_yml}"
        download ${ipaddr} "${port}" "${user}" "${remote_yml}" "${local_yml}"
    }
}

init_kube_calico_cni() {
    local user=${1}
    local port=${2}
    local ipaddr="${3}"
    local pod_cidr=${4}
    local svc_cidr=${5}
    local insec_registry=${6}
    local crossnet_method=${7}
    vinfo_msg <<EOF
****** ${ipaddr} init calico() cni svc: ${svc_cidr}, pod:${pod_cidr}.
EOF
    info_msg "calico need do, when NetworkManager present\n"
#     cat <<EOF > calico host /etc/NetworkManager/conf.d/calico.conf || true
# [keyfile]
# unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
# EOF
    prepare_yml "${user}" "${port}" "${ipaddr}" "${L_CALICO_YML}" "${R_CALICO_YML}" "${CALICO_YML}"
    prepare_yml "${user}" "${port}" "${ipaddr}" "${L_CALICO_CUST_YML}" "${R_CALICO_CUST_YML}" "${CALICO_CUST_YML}"
    ssh_func "${user}@${ipaddr}" "${port}" init_calico_cni "${svc_cidr}" "${pod_cidr}" "${R_CALICO_YML}" "${R_CALICO_CUST_YML}" "${insec_registry}" "${crossnet_method}"
}
k8s_only_add_worker() {
    local user=${1}
    local port=${2}
    local ipaddr=${3}
    local newnodes=($(array_print ${4}))
    local apiserver=${5}
    [ "$(array_size newnodes)" -gt "0" ] || { info_msg "No worker need add\n"; return 0; }
    local token=$(ssh_func "${user}@${ipaddr}" "${port}" "kubeadm token create")
    local sha_hash=$(ssh_func "${user}@${ipaddr}" "${port}" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")
    # reupload certs
    ssh_func "${user}@${ipaddr}" "${port}" "kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n 1"
    for ipaddr in $(array_print newnodes); do
        info2_msg "****** ${ipaddr} add worker(${apiserver})\n"
        ssh_func "${user}@${ipaddr}" "${port}" add_k8s_worker "${apiserver}" "${token}" "${sha_hash}"
    done
}
k8s_only_add_master() {
    local user=${1}
    local port=${2}
    local ipaddr=${3}
    local newnodes=($(array_print ${4}))
    local apiserver=${5}
    [ "$(array_size newnodes)" -gt "0" ] || { info_msg "No master need add\n"; return 0; }
    local token=$(ssh_func "${user}@${ipaddr}" "${port}" "kubeadm token create")
    local sha_hash=$(ssh_func "${user}@${ipaddr}" "${port}" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")
    # reupload certs
    local certs=$(ssh_func "${user}@${ipaddr}" "${port}" "kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n 1")
    for ipaddr in $(array_print newnodes); do
        info1_msg "****** ${ipaddr} add master(${apiserver})\n"
        ssh_func "${user}@${ipaddr}" "${port}" add_k8s_master "${apiserver}" "${token}" "${sha_hash}" "${certs}"
    done
}
init_kube_cluster() {
    local user=${1}
    local port=${2}
    local master_nodes=($(array_print ${3}))
    local worker_nodes=($(array_print ${4}))
    local apiserver=${5}
    local pod_cidr=${6}
    local skip_proxy=${7}
    local svc_cidr=${8}
    local insec_registry=${9}
    local etcd=($(array_print ${10}))
    [ "$(array_size master_nodes)" -gt "0" ] || return 1
    local ipaddr=${master_nodes[0]}
    info_msg "****** ${ipaddr} init first master(${apiserver:-no apiserver define})\n"
    [ "$(array_size etcd)" -gt "0" ] && {
        ssh_func "${user}@${ipaddr}" "${port}" init_first_k8s_master_use_extern_etcd  "${apiserver}" "${skip_proxy}" "${pod_cidr}" "${svc_cidr}" "${insec_registry}" ${etcd[@]}
    } || {
        ssh_func "${user}@${ipaddr}" "${port}" init_first_k8s_master "${apiserver}" "${skip_proxy}" "${pod_cidr}" "${svc_cidr}" "${insec_registry}"
    }
    local new_masters=()
    for ((i=1;i<$(array_size master_nodes);i++)); do new_masters+=(${master_nodes[$i]}); done
    [ -z "${apiserver}" ] && apiserver=$(ssh_func "${user}@${ipaddr}" "${port}" 'sed -n "s/\s*server\s*:\s*http[s]*:\/\/\(.*\)/\1/p" /etc/kubernetes/kubelet.conf')
    k8s_only_add_master "${user}" "${port}" ${ipaddr} new_masters "${apiserver}"
    k8s_only_add_worker "${user}" "${port}" ${ipaddr} worker_nodes "${apiserver}"
}

usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
        ${G}env:${N}
            ${G}SUDO=${N}   default undefine
        -m|--master       * * *  <ip>   master nodes, support multi nodes
        -w|--worker       * X    <ip>   worker nodes, support multi nodes
        --etcd                   <url>  external etcd cluster addesses, support multi nodes
                                        exam: https://192.168.168.152:2379
        -s|--svc_cidr     X X    <cidr> service cidr, default 10.96.0.0/12
        -p|--pod_cidr     X X *  <cidr> calico cni, pod_cidr
        --enable_schedule               enable master node scheduling
        --insec_registry         <str>  insecurity registry(http/no auth)
        --nameserver             <ip>   k8s nodes nameserver, /etc/resolv.conf
        --calico          X X    <str>  calico crossnet method, use this parm mean use calico cni
                                        IPIPCrossSubnet/VXLANCrossSubnet/IPIP/VXLAN/None
        --apiserver       X X    <str>  k8s cluster api-server-endpoint
                                        no set use first master ipaddress, so control plane can only one!!!
                                        SUGGEST: use domain name. apiserver.demo.org:6443
        --vip                    <str>  apiserver extra ip or dns_name. demo: 172.16.0.155,myserver
                                        in apiserver certificate Subject Alternative Names
        --skip_proxy      X X           skip install kube-proxy, default false
        --ipvs            X X           kube-proxy mode ipvs, default false
        --only_add_master X * X  <ip>   only add master to exist k8s cluster(--master nodes)
                                        <ip> is a exists master nodes
        --only_add_worker * X X         only add worker to exist k8s cluster(--worker nodes)
        -U|--user                <user> ssh user, default root
        -P|--port                <int>  ssh port, default 60022
        --password               <str>  ssh password(default use sshkey)
        --teardown               <ip>   remove all k8s config, support multi nodes
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        DOC:
            https://kubernetes.io/zh-cn/docs/home/
            如果在运行kubeadm init之前存在给定的证书和私钥对,kubeadm 将不会重写它们,kubeadm将使用此CA对其余证书进行签名
                /etc/kubernetes/pki/ca.crt
                /etc/kubernetes/pki/ca.key
            cephfs_pv.sh && nfs_pv.sh && iscsi_pv.sh
        ${Y}EXAM:
    on master nodes:
        # add fast disk(ssd/nvme)
        mkdir -p /var/lib/etcd/
        disk=/dev/vdb
        mkfs.xfs -f \${disk}
        echo "UUID=\$(blkid -s UUID -o value \${disk}) /var/lib/etcd xfs noexec,nodev,noatime,nodiratime  0 2" >> /etc/fstab
    on all nodes:
        echo '192.168.168.xxx     registry.local'>> /etc/hosts
        wget --no-check-certificate -O /etc/yum.repos.d/cnap.repo http://registry.local/cnap/cnap.repo
        yum -y --enablerepo=cnap install tsd_cnap_v1.27.3 bash-completion
            yum -y install nfs-utils nfs4-acl-tools # # nfs pv
            yum -y install iscsi-initiator-utils    # # iscsi pv
            yum -y install ceph-common              # # cephfs pv
# # init new cluster
${SCRIPTNAME} -m 192.168.168.150 --pod_cidr 172.16.0.0/24 --ipvs --insec_registry 192.168.168.250 --apiserver myserver:6443
# # make api ha
post_k8s_cluster_api_ha.sh
# # add worker in exists cluster
${SCRIPTNAME} --only_add_worker -m 192.168.168.150 -w 192.168.168.151 --insec_registry 192.168.168.250
# # add master in exists cluster
${SCRIPTNAME} --only_add_master 192.168.168.150 -m 192.168.168.152 --insec_registry 192.168.168.250${N}
EOF
)"; echo -e "${usage_doc}"
    exit 1
}
verify_apiserver() {
    local apiserver=${1}
    local tname="" tport=""
    IFS=':' read -r tname tport <<< "${apiserver}"
    [ -z "${tname}" ] && exit_msg "apiserver check failed, name\n"
    is_integer "${tport}" || exit_msg "apiserver check failed, port\n"
    str_equal ${tport} 6443 || warn_msg "apiport${tport} is not 6443, sould has a Loadbalancer redirect it!!!!\n"
    return 0
}
verify_calico() {
    local crossnet_method=${1}
    case "$1" in
        IPIPCrossSubnet)  return 0;;
        VXLANCrossSubnet) return 0;;
        IPIP)             return 0;;
        VXLAN)            return 0;;
        None)             return 0;;
        *)                exit_msg "unknow calico mode\n";;
    esac
}
main() {
    local etcd=()
    local master=() worker=() teardown=() svc_cidr="" pod_cidr="" insec_registry="" nameserver="" apiserver="" crossnet_method="" only_add_master=""
    unset API_VIP
    local skip_proxy=false ipvs=false only_add_worker=false enable_schedule=false
    local user=root port=60022
    local opt_short="m:w:s:p:U:P:"
    local opt_long="master:,worker:,svc_cidr:,pod_cidr:,insec_registry:,nameserver:,calico:,apiserver:,skip_proxy,ipvs,only_add_worker,only_add_master:,password:,teardown:,user:,port:,enable_schedule,etcd:,vip:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)     shift; master+=(${1}); shift;;
            -w | --worker)     shift; worker+=(${1}); shift;;
            -s | --svc_cidr)   shift; svc_cidr=${1}; shift;;
            -p | --pod_cidr)   shift; pod_cidr=${1}; shift;;
            --etcd)            shift; etcd+=(${1}); shift;;
            --enable_schedule) shift; enable_schedule=true;;
            --insec_registry)  shift; insec_registry=${1}; shift;;
            --nameserver)      shift; nameserver=${1}; shift;;
            --calico)          shift; verify_calico "${1}" && crossnet_method=${1}; shift;;
            --apiserver)       shift; verify_apiserver "${1}" && apiserver=${1}; shift;;
            --vip)             shift; export API_VIP=${1}; shift;;
            --skip_proxy)      shift; skip_proxy=true;;
            --ipvs)            shift; ipvs=true;;
            --only_add_worker) shift; only_add_worker=true;;
            --only_add_master) shift; only_add_master=${1}; shift;;
            -U | --user)       shift; user=${1}; shift;;
            -P | --port)       shift; port=${1}; shift;;
            --password)        shift; set_sshpass "${1}"; shift;;
            --teardown)        shift; teardown+=(${1}); shift;;
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
    local ipaddr=""
    # # teardown
    for ipaddr in "${teardown[@]}"; do
        info_msg "${ipaddr} teardown all k8s config!\n"
        ssh_func "${user}@${ipaddr}" "${port}" "teardown"
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    [ "$(array_size master)" -gt "0" ] || usage "at least one master"
    [ "$(array_size etcd)" -gt "0" ] && {
        info_msg "Use external ETCD\n"
        file_exists "ca.pem" || exit_msg "etcd ca.pem no found\n";
        file_exists "etcd.pem" || exit_msg "etcd etcd.pem no found\n";
        file_exists "etcd.key" || exit_msg "etcd etcd.key no found\n";
    }
    [ -z "${only_add_master}" ] || {
        # # only add master in exist k8s cluster
        apiserver=$(ssh_func "${user}@${only_add_master}" "${port}" 'sed -n "s/\s*server\s*:\s*http[s]*:\/\/\(.*\)/\1/p" /etc/kubernetes/kubelet.conf')
        for ipaddr in $(array_print master); do
            info_msg "****** ${ipaddr} pre valid host env\n"
            ssh_func "${user}@${ipaddr}" "${port}" pre_conf_k8s_host "${only_add_master}" "${apiserver}" "${nameserver}" "${insec_registry}"
            [ "$(array_size etcd)" -gt "0" ] && {
                upload "ca.pem" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
                upload "etcd.pem" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
                upload "etcd.key" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
            }
        done
        k8s_only_add_master "${user}" "${port}" "${only_add_master}" master "${apiserver}"
        info_msg "ONLY ADD MASTER ALL DONE\n"
        return 0
    }
    ${only_add_worker} && {
        # # only add worker in exist k8s cluster
        [ "$(array_size worker)" -gt "0" ] || usage "only worker mode, at least one worker input"
        apiserver=$(ssh_func "${user}@${master[0]}" "${port}" 'sed -n "s/\s*server\s*:\s*http[s]*:\/\/\(.*\)/\1/p" /etc/kubernetes/kubelet.conf')
        for ipaddr in $(array_print worker); do
            info_msg "****** ${ipaddr} pre valid host env\n"
            ssh_func "${user}@${ipaddr}" "${port}" pre_conf_k8s_host "${master[0]}" "${apiserver}" "${nameserver}" "${insec_registry}"
            [ "$(array_size etcd)" -gt "0" ] && {
                upload "ca.pem" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
                upload "etcd.pem" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
                upload "etcd.key" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
            }
        done
        k8s_only_add_worker "${user}" "${port}" "${master[0]}" worker "${apiserver}"
        info_msg "ONLY ADD WORKER ALL DONE\n"
        return 0
    }
    # # init new k8s cluster
    [ -z "${pod_cidr}" ] && usage "need pod_cidr"
    [ -z "${crossnet_method}" ] || { file_exists "${L_CALICO_YML}" && file_exists "${L_CALICO_CUST_YML}" || confirm "${L_CALICO_YML}/${L_CALICO_CUST_YML} not exists, continue? (timeout 10,default N)?" 10 || exit_msg "BYE!\n"; }
    [ -z "${insec_registry}" ] && { confirm "private registry not set, continue? (timeout 10,default N)?" 10 || exit_msg "BYE!\n"; }
    for ipaddr in $(array_print master) $(array_print worker); do
        info_msg "****** ${ipaddr} pre valid host env\n"
        ssh_func "${user}@${ipaddr}" "${port}" pre_conf_k8s_host "${master[0]}" "${apiserver}" "${nameserver}" "${insec_registry}"
        [ "$(array_size etcd)" -gt "0" ] && {
            upload "ca.pem" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
            upload "etcd.pem" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
            upload "etcd.key" "${ipaddr}" "${port}" "${user}" "/etc/kubernetes/pki/etcd/"
        }
    done
    init_kube_cluster "${user}" "${port}" master worker "${apiserver}" "${pod_cidr}" "${skip_proxy}" "${svc_cidr}" "${insec_registry}" etcd
    ${skip_proxy} || { ${ipvs} && ssh_func "${user}@${master[0]}" "${port}" modify_kube_proxy_ipvs; }
    ${enable_schedule} && { ssh_func "${user}@${master[0]}" "${port}" enbale_pod_scheduling_on_master; }
    [ -z "${crossnet_method}" ] || init_kube_calico_cni "${user}" "${port}" "${master[0]}" "${pod_cidr}" "${svc_cidr}" "${insec_registry}" "${crossnet_method}"
    info_msg "export k8s configuration\n"
    ssh_func "${user}@${master[0]}" "${port}" 'kubeadm config print init-defaults'
    ssh_func "${user}@${master[0]}" "${port}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl cluster-info"
    info_msg "use: calico_rr.sh for modify calico to bgp-rr with ebpf\n"
    info_msg "diag: scp ./kube-proxy\:v1.27.3.tar.gz user@ip:~/\n"
    info_msg "diag: kubectl describe configmaps kubeadm-config -n kube-system\n"
    info_msg "diag: kubectl get nodes -o wide\n"
    info_msg "diag: kubectl get pods --all-namespaces -o wide\n"
    info_msg "diag: kubectl get daemonsets.apps -n calico-system calico-node -o yaml\n"
    info_msg "diag: kubectl get configmaps -n calico-system  -o yaml\n"
    info_msg "diag: kubectl logs -n kube-system coredns-xxxx\n"
    info_msg "diag: kubectl describe -n kube-system pod coredns-xxxx\n"
    info_msg "diag: journalctl -f -u kubelet\n"
    info_msg "diag: journalctl --rotate # rotate log\n"
    info_msg "diag: journalctl --vacuum-time=10s # clear log 10s ago\n"
    info_msg "diag: crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock\n"
    info_msg "diag: cat /etc/crictl.yaml\n"
    info_msg "diag: crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a\n"
    info_msg "diag: crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock logs xxxx\n"
    info_msg "diag: kubectl get svc\n"
    info_msg "diag: kubectl -n kube-system get rs\n"
    info_msg "diag: kubectl -n kube-system scale --replicas=3 rs/coredns-xxxx\n"
    info_msg "diag: kubectl -n calico-system get configmaps\n"
    info_msg "diag: kubectl edit configmaps -n kube-system kubeadm-config\n"
    info_msg "diag: kubectl edit configmaps -n kube-system kube-proxy\n"
    info_msg "diag: kubectl edit deployment -n kube-system coredns\n"
    info_msg "diag: kubectl edit service -n kube-system kube-dns\n"
    info_msg "diag: kubectl get nodes\n"
    info_msg "diag: kubectl edit node <node>\n"
    info_msg "diag: kubectl -n kube-system exec -it etcd-node-xxxx -- /bin/sh\n"
    info_msg "diag: calicoctl get workloadendpoints -A\n"
    info_msg "diag: calicoctl node status\n"
    info_msg "diag: kubectl get service --all-namespaces # -o yaml\n"
    info_msg "diag: kubectl get configmap --all-namespaces # -o yaml\n"
    cat <<EOF
# certificate expiration date
kubeadm certs check-expiration
# 使Master Node参与工作负载
kubectl taint nodes --all node-role.kubernetes.io/master-
# 禁止master部署pod
kubectl taint nodes k8s node-role.kubernetes.io/master=true:NoSchedule
kubectl describe node srv150
kubectl -n kube-system edit configmaps coredns -o yaml
# # below add ths end of Corefile, other wise somethine wrong ks-api
#    hosts {
#      fallthrough     # 插件无法处理查询时继续查询下一个插件或者返回一个NXDOMAIN响应
#      # If you want to pass the request to the rest of the plugin chain
#      # if there is no match in the hosts plugin, you must specify the fallthrough option.
#      192.168.168.150 k8sapi.local.com
#    }
确认master是否有污点,去除后Master可以参与调度
kubectl describe node <master> | grep Taint
去除污点
kubectl taint nodes <master> node-role.kubernetes.io/master:NoSchedule-
# 删除污点
kubectl taint nodes --all node-role.kubernetes.io/master-
# 不参与调度
kubectl label nodes k8s-master node-role.kubernetes.io/worker=
# 驱逐
kubectl drain <node> --delete-local-data --ignore-daemonsets --force
# # kubectl uncordon <node> #make it schedulable again
# 将node置为SchedulingDisabled不可调度状态
kubectl cordon <node>
# # arm64环境，修改kubesphere的default-http-backend运行image是amd64,bug
kubectl -n kubesphere-controls-system  get all
kubectl -n  kubesphere-controls-system get deployments.apps default-http-backend -o yaml | \
    sed 's|defaultbackend-amd64|defaultbackend-arm64|g' > backend.yaml
    kubectl delete -f backend.yaml; kubectl apply -f backend.yaml
# # 删除worker1结点
kubectl cordon worker1
kubectl drain  worker1 --delete-local-data --ignore-daemonsets --force
kubectl delete node worker1
生成初始化配置文件
kubeadm config print init-defaults > kubeadm-config.yaml
查看生效的配置文件
kubectl -n kube-system get cm kubeadm-config -o yaml
# fix core dns run on on node
kubectl -n kube-system rollout restart deployment coredns
kubectl -n kube-system rollout restart daemonsets,deployments
# change calico v3.21.4 ipipMode
calicoctl patch  IPPool default-ipv4-ippool  -p "{\"spec\": {\"ipipMode\": \"CrossSubnet\"}}"
kubectl patch installation.operator.tigera.io default --type merge -p '{"spec":{"calicoNetwork":{"mtu":1500}}}'
etcdctl --endpoints "https://127.0.0.1:2379" --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key member list
# 使用命令查看是否触发限流等待
kubectl get --raw /debug/api_priority_and_fairness/dump_priority_levels
# pod初始化失败相关的事件
kubectl get events --all-namespaces
# pod的资源使用指标
kubectl top pods -A
# API服务器健康状况
kubectl get --raw=/healthz
EOF
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
