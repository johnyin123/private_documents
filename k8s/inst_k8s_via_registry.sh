#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2023-07-31T12:52:27+08:00]:inst_k8s_via_registry.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
SSH_PORT=${SSH_PORT:-60022}
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
    sed -i "s|spec\s*:\s*$|spec:\n  registry: ${insec_registry}|g" "${calico_cust_yml}"
    sed -i "s|image\s*:.*operator|image: ${insec_registry=}/tigera/operator|g" "${calico_yml}"
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl create -f "${calico_yml}" # need wait a moment, avoid cust yml error
    kubectl get nodes -o wide || true
    kubectl get pods --all-namespaces -o wide || true
    kubectl create -f "${calico_cust_yml}"
    calicoctl node status || true
    rm -f "${calico_yml}" "${calico_cust_yml}" || true
}
pre_conf_k8s_host() {
    local apiserver=${1}
    local nameserver=${2}
    local insec_registry=${3}
    echo "127.0.0.1 localhost ${HOSTNAME:-$(hostname)}" > /etc/hosts
    [ -z "${nameserver}" ] || echo "nameserver ${nameserver}" > /etc/resolv.conf
    touch /etc/resolv.conf || true
    swapoff -a
    sed -i "/\s*swap\s/d" /etc/fstab
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
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
    local pausekey=$(kubeadm config images list --image-repository ${insec_registry}/google_containers --kubernetes-version=${k8s_version} 2>/dev/null | grep pause)
    echo "****PAUSE: ${pausekey}"
    # change sandbox_image on all nodes
    mkdir -vp /etc/containerd && containerd config default > /etc/containerd/config.toml || true
    sed -i -e "s|sandbox_image\s*=.*|sandbox_image = \"${pausekey}\"|g" /etc/containerd/config.toml
    sed -i 's/SystemdCgroup\s*=.*$/SystemdCgroup = true/g' /etc/containerd/config.toml
    sed -i -E "s|(^\s*)\[(plugins.*registry.mirrors)\]$|\1[\2]\n\1  [\2.\"${insec_registry}\"]\n\1    endpoint = [\"http://${insec_registry}\"]|g" /etc/containerd/config.toml
    systemctl daemon-reload || true
    systemctl restart containerd.service || true
    systemctl enable containerd.service || true
    systemctl enable kubelet.service
    systemctl disable firewalld --now || true
}

gen_k8s_join_cmds() {
    local token=$(kubeadm token create)
    local sha_hash=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    local certs=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n 1)
    local api_srv=$(sed -n "s/\s*server:\s*\(.*\)/\1/p" /etc/kubernetes/kubelet.conf)
    echo kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash} --control-plane --certificate-key ${certs}
    echo kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash}
}

modify_kube_proxy_ipvs() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl -n kube-system get configmaps kube-proxy -o yaml | \
    sed 's/mode:\s*"[^"]*"/mode: "ipvs"/g' | \
    kubectl apply -f -
    kubectl -n kube-system delete pod -l k8s-app=kube-proxy
}

init_first_k8s_master() {
    local api_srv=${1} # apiserver dns-name:port
    local skip_proxy=${2}
    local pod_cidr=${3}
    local svc_cidr=${4}
    local insec_registry=${5}
    local opts="--control-plane-endpoint ${api_srv} --upload-certs ${pod_cidr:+--pod-network-cidr=${pod_cidr}} ${svc_cidr:+--service-cidr ${svc_cidr}} --apiserver-advertise-address=0.0.0.0 --image-repository=${insec_registry}/google_containers"
    ${skip_proxy} && opts="--skip-phases=addon/kube-proxy ${opts}" 
    local k8s_version=$(kubelet --version | awk '{ print $2}')
    kubeadm init --kubernetes-version ${k8s_version} ${opts}
    echo "FIX 'kubectl get cs' Unhealthy"
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-controller-manager.yaml
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-scheduler.yaml
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" > /etc/profile.d/k8s.sh
    echo "source <(kubectl completion bash)" >> /etc/profile.d/k8s.sh
    chmod 644 /etc/profile.d/k8s.sh
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "certificate expiration date"
    kubeadm certs check-expiration
    kubectl -n kube-system get rs || true
    kubectl cluster-info || true
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
    rm -fr /etc/cni/net.d/* /etc/profile.d/k8s.sh || true
    # # # remove calico
    # kubectl delete -f calico.yaml
    modprobe -r ipip || true
    rm -rf /var/lib/cni/ || true
    rm -rf /etc/cni/net.d/* || true
    # systemctl restart kubelet
}
# remote execute function end!
################################################################################
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

prepare_yml() {
    local ipaddr=${1}
    local local_yml=${2}
    local remote_yml=${3}
    local yml_url=${4}
    [ -e "${local_yml}" ] && {
        upload "${local_yml}" "${ipaddr}" "${SSH_PORT}" "root" "${remote_yml}"
    } || {
        warn_msg "Local yaml ${local_yml} NOT EXIST!!, remote download it.\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "wget -q ${yml_url} -O ${remote_yml}"
        download ${ipaddr} "${SSH_PORT}" "root" "${remote_yml}" "${local_yml}"
    }
}

init_kube_calico_cni() {
    local master=($(array_print ${1}))
    local pod_cidr=${2}
    local svc_cidr=${3}
    local insec_registry=${4}
    local crossnet_method=${5}
    local ipaddr="${master[0]}"
    CALICO_YML="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml"
    CALICO_CUST_YML="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml"
    L_CALICO_YML="tigera-operator.yaml"
    R_CALICO_YML="/tmp/tigera-operator.yaml"
    L_CALICO_CUST_YML="custom-resources.yaml"
    R_CALICO_CUST_YML="/tmp/custom-resources.yaml"
    vinfo_msg <<EOF
****** ${ipaddr} init calico() cni svc: ${svc_cidr}, pod:${pod_cidr}.
EOF
    info_msg "calico need do, when NetworkManager present\n"
#     cat <<EOF > calico host /etc/NetworkManager/conf.d/calico.conf || true
# [keyfile]
# unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
# EOF
    prepare_yml "${ipaddr}" "${L_CALICO_YML}" "${R_CALICO_YML}" "${CALICO_YML}"
    prepare_yml "${ipaddr}" "${L_CALICO_CUST_YML}" "${R_CALICO_CUST_YML}" "${CALICO_CUST_YML}"
    ssh_func "root@${master[0]}" "${SSH_PORT}" init_calico_cni "${svc_cidr}" "${pod_cidr}" "${R_CALICO_YML}" "${R_CALICO_CUST_YML}" "${insec_registry}" "${crossnet_method}"
}

init_kube_cluster() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local api_srv=${3}
    local pod_cidr=${4}
    local skip_proxy=${5}
    local svc_cidr=${6}
    local insec_registry=${7}
    [ "$(array_size master)" -gt "0" ] || return 1
    local ipaddr=$(array_get master 0)
    info_msg "****** ${ipaddr} init first master(${api_srv})\n"
    IFS=':' read -r tname tport <<< "${api_srv}"
    local hosts="${ipaddr} ${tname}"
    ssh_func "root@${ipaddr}" "${SSH_PORT}" "echo ${hosts}>> /etc/hosts"
    ssh_func "root@${ipaddr}" "${SSH_PORT}" init_first_k8s_master "${api_srv}" "${skip_proxy}" "${pod_cidr}" "${svc_cidr}" "${insec_registry}"
    local token=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "kubeadm token create")
    local sha_hash=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")
    # reupload certs
    local certs=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n 1")
    for ((i=1;i<$(array_size master);i++)); do
        ipaddr=$(array_get master ${i})
        info1_msg "****** ${ipaddr} add master(${api_srv})\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "echo ${hosts}>> /etc/hosts"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" add_k8s_master "${api_srv}" "${token}" "${sha_hash}" "${certs}"
    done
    for ipaddr in $(array_print worker); do
        info2_msg "****** ${ipaddr} add worker(${api_srv})\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "echo ${hosts} >> /etc/hosts"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" add_k8s_worker "${api_srv}" "${token}" "${sha_hash}"
    done
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
            SSH_PORT        default 60022
        -m|--master         *  <ip>   master nodes, support multi nodes
        -w|--worker            <ip>   worker nodes, support multi nodes
        -s|--svc_cidr          <cidr> servie cidr, default 10.96.0.0/12
        -p|--pod_cidr       *  <cidr> calico cni, pod_cidr
        --insec_registry    *  <str>  insecurity registry(http/no auth)
        --nameserver        *  <ip>   k8s nodes nameserver, /etc/resolv.conf
        --calico)              <str>  calico crossnet method, default IPIPCrossSubnet
                                      IPIPCrossSubnet/VXLANCrossSubnet/IPIP/VXLAN/None
        --apiserver            <str>  k8s cluster api-server-endpoint
                                      default "k8sapi.local.com:6443"
                                      k8sapi.local.com is first master node, store in /etc/hosts(all masters&workers)
                                      u should make a loadbalance to all masters later,
        --skip_proxy                  skip install kube-proxy, default false
        --ipvs                        kube-proxy mode ipvs, default false
        --gen_join_cmds               only generate join commands
        --password             <str>  ssh password(default use sshkey)
        --teardown             <ip>   remove all k8s config, support multi nodes
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local master=() worker=() teardown=() svc_cidr="" pod_cidr="" insec_registry="" nameserver=""
    local crossnet_method=IPIPCrossSubnet apiserver="k8sapi.local.com:6443" skip_proxy=false ipvs=false gen_join_cmds=false
    local opt_short="m:w:s:p:"
    local opt_long="master:,worker:,svc_cidr:,pod_cidr:,insec_registry:,nameserver:,calico:,apiserver:,skip_proxy,ipvs,gen_john_cmds,password:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)    shift; master+=(${1}); shift;;
            -w | --worker)    shift; worker+=(${1}); shift;;
            -s | --svc_cidr)  shift; svc_cidr=${1}; shift;;
            -p | --pod_cidr)  shift; pod_cidr=${1}; shift;;
            --insec_registry) shift; insec_registry=${1}; shift;;
            --nameserver)     shift; nameserver=${1}; shift;;
            --calico)         shift; crossnet_method=${1}; shift;;
            --apiserver)      shift; apiserver=${1}; shift;;
            --skip_proxy)     shift; skip_proxy=true;;
            --ipvs)           shift; ipvs=true;;
            --gen_join_cmds)  shift; gen_join_cmds=true;; 
            --password)       shift; set_sshpass "${1}"; shift;;
            --teardown)       shift; teardown+=(${1}); shift;;
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
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "teardown"
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    # # gen join cmd
    [ "$(array_size master)" -gt "0" ] || usage "at least one master"
    ${gen_join_cmds} && {
        ssh_func "root@${master[0]}" "${SSH_PORT}" gen_k8s_join_cmds
        info_msg "GEN_CMDS OK\n"
        return 0
    }
    # # init new k8s cluster
    [ -z "${insec_registry}" ] || [ -z "${nameserver}" ] || [ -z "${pod_cidr}" ] && usage "need insec_registry/nameserver/pod_cidr"
    confirm "Confirm NEW init k8s env(timeout 10,default N)?" 10 || exit_msg "BYE!\n"
    for ipaddr in $(array_print master) $(array_print worker); do
        info_msg "****** ${ipaddr} pre valid host env\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" pre_conf_k8s_host "${apiserver}" "${nameserver}"  "${insec_registry}"
    done
    init_kube_cluster master worker "${apiserver}" "${pod_cidr}" "${skip_proxy}" "${svc_cidr}" "${insec_registry}"
    ${skip_proxy} || { ${ipvs} && ssh_func "root@${master[0]}" "${SSH_PORT}" modify_kube_proxy_ipvs; }
    init_kube_calico_cni master "${pod_cidr}" "${svc_cidr}" "${insec_registry}" "${crossnet_method}"
    info_msg "export k8s configuration\n"
    ssh_func "root@${master[0]}" "${SSH_PORT}" 'kubeadm config print init-defaults'
    ssh_func "root@${master[0]}" "${SSH_PORT}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl cluster-info"
    info_msg "use: calico_rr.sh for modify calico to bgp-rr with ebpf\n"
    info_msg "diag: scp ./kube-proxy\:v1.27.3.tar.gz root@ip:~/\n"
    info_msg "diag: kubectl describe configmaps kubeadm-config -n kube-system\n"
    info_msg "diag: kubectl get nodes -o wide\n"
    info_msg "diag: kubectl get pods --all-namespaces -o wide\n"
    info_msg "diag: kubectl get daemonsets.apps -n calico-system calico-node -o yaml\n"
    info_msg "diag: kubectl get configmaps -n calico-system  -o yaml\n"
    info_msg "diag: kubectl logs -n kube-system coredns-xxxx\n"
    info_msg "diag: kubectl describe -n kube-system pod coredns-xxxx\n"
    info_msg "diag: journalctl -f -u kubelet\n"
    info_msg "diag: crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock\n"
    info_msg "diag: cat /etc/crictl.yaml\n"
    info_msg "diag: crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a\n"
    info_msg "diag: crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock logs xxxx\n"
    info_msg "diag: kubectl get svc\n"
    info_msg "diag: kubectl -n kube-system get rs\n"
    info_msg "diag: kubectl -n kube-system scale --replicas=3 rs/coredns-xxxx\n"
    info_msg "diag: kubectl -n calico-system get configmaps\n"
    info_msg "diag: kubectl -n kube-system edit configmaps kube-proxy -o yaml\n"
    info_msg "diag: kubectl -n kube-system exec -it etcd-node-xxxx -- /bin/sh\n"
    info_msg "diag: calicoctl get workloadendpoints -A\n"
    info_msg "diag: calicoctl node status\n"
    info_msg "diag: kubectl get service --all-namespaces # -o yaml\n"
    info_msg "diag: kubectl get configmap --all-namespaces # -o yaml\n"
    cat <<EOF
# 使Master Node参与工作负载
kubectl taint nodes --all node-role.kubernetes.io/master-
# 禁止master部署pod
kubectl taint nodes k8s node-role.kubernetes.io/master=true:NoSchedule
kubectl describe node srv150
kubectl -n kube-system edit configmaps coredns -o yaml
#    hosts {
#      192.168.168.150 k8sapi.local.com
#    }
确认master是否有污点
kubectl describe node <master> | grep Taint
去除污点
kubectl taint nodes <master> node-role.kubernetes.io/master:NoSchedule-
EOF
    info_msg "ALL DONE\n"
    return 0
}
main "$@"