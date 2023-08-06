#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("bd29676[2023-08-06T12:02:13+08:00]:inst_k8s_via_registry.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
SSH_PORT=${SSH_PORT:-60022}

CALICO_YML="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml"
CALICO_CUST_YML="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml"
L_CALICO_YML="tigera-operator.yaml"
R_CALICO_YML="/tmp/tigera-operator.yaml"
L_CALICO_CUST_YML="custom-resources.yaml"
R_CALICO_CUST_YML="/tmp/custom-resources.yaml"

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
    echo "127.0.0.1 localhost ${HOSTNAME:-$(hostname)}" > /etc/hosts
    # skip ip address
    ip route get "${tname:-127.0.0.1}" &>/dev/null || { echo "${master} ${tname}" >> /etc/hosts; }
    [ -z "${nameserver}" ] || echo "nameserver ${nameserver}" > /etc/resolv.conf
    touch /etc/resolv.conf || true
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
    [ -z "sec_registry}" ] || sed -i -E "s|(^\s*)\[(plugins.*registry.mirrors)\]$|\1[\2]\n\1  [\2.\"${insec_registry}\"]\n\1    endpoint = [\"http://${insec_registry}\"]|g" /etc/containerd/config.toml
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

init_first_k8s_master() {
    local apiserver=${1} # apiserver dns-name:port
    local skip_proxy=${2}
    local pod_cidr=${3}
    local svc_cidr=${4}
    local insec_registry=${5}
    local opts="${apiserver:+--control-plane-endpoint ${apiserver}} --upload-certs ${pod_cidr:+--pod-network-cidr=${pod_cidr}} ${svc_cidr:+--service-cidr ${svc_cidr}} --apiserver-advertise-address=0.0.0.0 ${insec_registry:+--image-repository=${insec_registry}/google_containers}"
    ${skip_proxy} && opts="--skip-phases=addon/kube-proxy ${opts}" 
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
    rm -fr /root/.kube /etc/cni/net.d/* /etc/profile.d/k8s.sh || true
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
    local ipaddr="${1}"
    local pod_cidr=${2}
    local svc_cidr=${3}
    local insec_registry=${4}
    local crossnet_method=${5}
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
    ssh_func "root@${ipaddr}" "${SSH_PORT}" init_calico_cni "${svc_cidr}" "${pod_cidr}" "${R_CALICO_YML}" "${R_CALICO_CUST_YML}" "${insec_registry}" "${crossnet_method}"
}
k8s_only_add_worker() {
    local ipaddr=${1}
    local newnodes=($(array_print ${2}))
    local apiserver=${3}
    [ "$(array_size newnodes)" -gt "0" ] || { info_msg "No worker need add\n"; return 0; }
    local token=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "kubeadm token create")
    local sha_hash=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")
    # reupload certs
    ssh_func "root@${ipaddr}" "${SSH_PORT}" "kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n 1"
    for ipaddr in $(array_print newnodes); do
        info2_msg "****** ${ipaddr} add worker(${apiserver})\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" add_k8s_worker "${apiserver}" "${token}" "${sha_hash}"
    done
}
k8s_only_add_master() {
    local ipaddr=${1}
    local newnodes=($(array_print ${2}))
    local apiserver=${3}
    [ "$(array_size newnodes)" -gt "0" ] || { info_msg "No master need add\n"; return 0; }
    local token=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "kubeadm token create")
    local sha_hash=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")
    # reupload certs
    local certs=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -n 1")
    for ipaddr in $(array_print newnodes); do
        info1_msg "****** ${ipaddr} add master(${apiserver})\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" add_k8s_master "${apiserver}" "${token}" "${sha_hash}" "${certs}"
    done
}
init_kube_cluster() {
    local master_nodes=($(array_print ${1}))
    local worker_nodes=($(array_print ${2}))
    local apiserver=${3}
    local pod_cidr=${4}
    local skip_proxy=${5}
    local svc_cidr=${6}
    local insec_registry=${7}
    [ "$(array_size master_nodes)" -gt "0" ] || return 1
    local ipaddr=${master_nodes[0]}
    info_msg "****** ${ipaddr} init first master(${apiserver:-no apiserver define})\n"
    ssh_func "root@${ipaddr}" "${SSH_PORT}" init_first_k8s_master "${apiserver}" "${skip_proxy}" "${pod_cidr}" "${svc_cidr}" "${insec_registry}"
    local new_masters=()
    for ((i=1;i<$(array_size master_nodes);i++)); do new_masters+=(${master_nodes[$i]}); done
    [ -z "${apiserver}" ] && apiserver=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" 'sed -n "s/\s*server\s*:\s*http[s]*:\/\/\(.*\)/\1/p" /etc/kubernetes/kubelet.conf')
    k8s_only_add_master ${ipaddr} new_masters "${apiserver}"
    k8s_only_add_worker ${ipaddr} worker_nodes "${apiserver}"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
            SSH_PORT        default 60022
        -m|--master       * * *  <ip>   master nodes, support multi nodes
        -w|--worker       * X    <ip>   worker nodes, support multi nodes
        -s|--svc_cidr     X X    <cidr> servie cidr, default 10.96.0.0/12
        -p|--pod_cidr     X X *  <cidr> calico cni, pod_cidr
        --insec_registry         <str>  insecurity registry(http/no auth)
        --nameserver             <ip>   k8s nodes nameserver, /etc/resolv.conf
        --calico          X X    <str>  calico crossnet method, default IPIPCrossSubnet
                                        IPIPCrossSubnet/VXLANCrossSubnet/IPIP/VXLAN/None
        --apiserver       X X    <str>  k8s cluster api-server-endpoint
                                        no set use first master ipaddress, so control plane can only one!!!
                                        SUGGEST: use domain name. apiserver.demo.org:6443
        --skip_proxy      X X           skip install kube-proxy, default false
        --ipvs            X X           kube-proxy mode ipvs, default false
        --only_add_master X * X  <ip>   only add master to exist k8s cluster(--master nodes)
                                        <ip> is a exists master nodes
        --only_add_worker * X X         only add worker to exist k8s cluster(--worker nodes)
        --password               <str>  ssh password(default use sshkey)
        --teardown               <ip>   remove all k8s config, support multi nodes
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        EXAM:
# # init new cluster
${SCRIPTNAME} --m 192.168.168.150 --pod_cidr 172.16.0.0/24 --ipvs --insec_registry 192.168.168.250 --apiserver myserver:6443
# # add worker in exists cluster
${SCRIPTNAME} --only_add_worker --m 192.168.168.150 -w 192.168.168.151 --insec_registry 192.168.168.250
# # add master in exists cluster
${SCRIPTNAME} --only_add_master 192.168.168.150 -m 192.168.168.152 --insec_registry 192.168.168.250
EOF
    exit 1
}
verify_apiserver() {
    local apiserver=${1}
    local tname="" tport=""
    IFS=':' read -r tname tport <<< "${apiserver}"
    [ -z "${tname}" ] && return 1
    is_integer "${tport}" || return 2
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
        *)                error_msg "unknow calico mode\n"; return 1;;
    esac
}
main() {
    local master=() worker=() teardown=() svc_cidr="" pod_cidr="" insec_registry="" nameserver="" apiserver="" crossnet_method="" only_add_master=""
    local skip_proxy=false ipvs=false only_add_worker=false
    local opt_short="m:w:s:p:"
    local opt_long="master:,worker:,svc_cidr:,pod_cidr:,insec_registry:,nameserver:,calico:,apiserver:,skip_proxy,ipvs,only_add_worker,only_add_master:,password:,teardown:,"
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
            --insec_registry)  shift; insec_registry=${1}; shift;;
            --nameserver)      shift; nameserver=${1}; shift;;
            --calico)          shift; verify_calico "${1}" && crossnet_method=${1}; shift;;
            --apiserver)       shift; verify_apiserver "${1}" && apiserver=${1}; shift;;
            --skip_proxy)      shift; skip_proxy=true;;
            --ipvs)            shift; ipvs=true;;
            --only_add_worker) shift; only_add_worker=true;;
            --only_add_master) shift; only_add_master=${1}; shift;;
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
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "teardown"
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    [ "$(array_size master)" -gt "0" ] || usage "at least one master"
    [ -z "${only_add_master}" ] || {
        # # only add master in exist k8s cluster
        apiserver=$(ssh_func "root@${only_add_master}" "${SSH_PORT}" 'sed -n "s/\s*server\s*:\s*http[s]*:\/\/\(.*\)/\1/p" /etc/kubernetes/kubelet.conf')
        for ipaddr in $(array_print master); do
            info_msg "****** ${ipaddr} pre valid host env\n"
            ssh_func "root@${ipaddr}" "${SSH_PORT}" pre_conf_k8s_host "${only_add_master}" "${apiserver}" "${nameserver}" "${insec_registry}"
        done
        k8s_only_add_master "${only_add_master}" master "${apiserver}"
        info_msg "ONLY ADD MASTER ALL DONE\n"
        return 0
    }
    ${only_add_worker} && {
        # # only add worker in exist k8s cluster
        [ "$(array_size worker)" -gt "0" ] || usage "only worker mode, at least one worker input"
        apiserver=$(ssh_func "root@${master[0]}" "${SSH_PORT}" 'sed -n "s/\s*server\s*:\s*http[s]*:\/\/\(.*\)/\1/p" /etc/kubernetes/kubelet.conf')
        for ipaddr in $(array_print worker); do
            info_msg "****** ${ipaddr} pre valid host env\n"
            ssh_func "root@${ipaddr}" "${SSH_PORT}" pre_conf_k8s_host "${master[0]}" "${apiserver}" "${nameserver}" "${insec_registry}"
        done
        k8s_only_add_worker "${master[0]}" worker "${apiserver}"
        info_msg "ONLY ADD WORKER ALL DONE\n"
        return 0
    }
    # # init new k8s cluster
    [ -z "${pod_cidr}" ] && usage "need pod_cidr"
    [ -z "${crossnet_method}" ] || { file_exists "${L_CALICO_YML}" && file_exists "${L_CALICO_CUST_YML}" || confirm "${L_CALICO_YML}/${L_CALICO_CUST_YML} not exists, continue? (timeout 10,default N)?" 10 || exit_msg "BYE!\n"; }
    [ -z "${insec_registry}" ] && { confirm "private registry not set, continue? (timeout 10,default N)?" 10 || exit_msg "BYE!\n"; }
    for ipaddr in $(array_print master) $(array_print worker); do
        info_msg "****** ${ipaddr} pre valid host env\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" pre_conf_k8s_host "${master[0]}" "${apiserver}" "${nameserver}" "${insec_registry}"
    done
    init_kube_cluster master worker "${apiserver}" "${pod_cidr}" "${skip_proxy}" "${svc_cidr}" "${insec_registry}"
    ${skip_proxy} || { ${ipvs} && ssh_func "root@${master[0]}" "${SSH_PORT}" modify_kube_proxy_ipvs; }
    [ -z "${crossnet_method}" ] || init_kube_calico_cni "${master[0]}" "${pod_cidr}" "${svc_cidr}" "${insec_registry}" "${crossnet_method}"
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
# certificate expiration date
kubeadm certs check-expiration
# 使Master Node参与工作负载
kubectl taint nodes --all node-role.kubernetes.io/master-
# 禁止master部署pod
kubectl taint nodes k8s node-role.kubernetes.io/master=true:NoSchedule
kubectl describe node srv150
kubectl -n kube-system edit configmaps coredns -o yaml
#    hosts {
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
# 将node置为SchedulingDisabled不可调度状态
kubectl cordon <node>
# # 删除结点
kubectl cordon worker1
kubectl drain  worker1 --delete-local-data --ignore-daemonsets --force
kubectl delete node worker1
EOF
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
