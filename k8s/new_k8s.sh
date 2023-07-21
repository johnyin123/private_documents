#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("ed8d813[2023-07-20T14:05:44+08:00]:new_k8s.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
SSH_PORT=${SSH_PORT:-60022}
HTTP_PROXY=${HTTP_PROXY:-}
K8S_VERSION=${K8S_VERSION:-v1.27.3} # $(kubelet --version | awk '{ print $2}')
# # predefine start
##OPTION_START
# dashboard url
declare -A DASHBOARD_MAP=(
    [dashboard:v2.0.0-beta1]=kubernetesui/dashboard:v2.0.0-beta1
    [metrics-scraper:v1.0.0]=kubernetesui/metrics-scraper:v1.0.0
)
DASHBOARD_YML="https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta1/aio/deploy/recommended.yaml"
L_DASHBOARD_YML="${DIRNAME}/${K8S_VERSION}/dashboard:v2.0.0-beta1.yml"
R_DASHBOARD_YML="/tmp/dashboard.yml"
# flannel_cni url
declare -A FLANNEL_MAP=(
    [flannel:v0.15.0]=quay.io/coreos/flannel:v0.15.0
)
FLANNEL_YML="https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
L_FLANNEL_YML="${DIRNAME}/${K8S_VERSION}/flannel:v0.15.0.yml"
R_FLANNEL_YML="/tmp/flannel.yml"
# ingress-nginx url
declare -A INGRESS_MAP=(
    [nginx-ingress-controller:v1.0.4]=k8s.gcr.io/ingress-nginx/controller:v1.0.4
    [kube-webhook-certgen:v1.1.1]=k8s.gcr.io/ingress-nginx/kube-webhook-certgen:v1.1.1
)
INGRESS_YML="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.0.4/deploy/static/provider/cloud/deploy.yaml"
L_INGRESS_YML="${DIRNAME}/${K8S_VERSION}/ingress-nginx:v1.0.4.yml"
R_INGRESS_YML="/tmp/ingress-nginx.yml"
# calico cni url
declare -A CALICO_MAP=(
    [cni:v3.26.1]=docker.io/calico/cni:v3.26.1
    [kube-controllers:v3.26.1]=docker.io/calico/kube-controllers:v3.26.1
    [node:v3.26.1]=docker.io/calico/node:v3.26.1
    [typha:v3.26.1]=docker.io/calico/typha:v3.26.1
    [csi:v3.26.1]=docker.io/calico/csi:v3.26.1
    [node-driver-registrar:v3.26.1]=docker.io/calico/node-driver-registrar:v3.26.1
    [apiserver:v3.26.1]=docker.io/calico/apiserver:v3.26.1
    [pod2daemon-flexvol:v3.26.1]=docker.io/calico/pod2daemon-flexvol:v3.26.1
)
declare -A CALICO_OPER_MAP=(
    [operator:v1.30.4]=quay.io/tigera/operator:v1.30.4
)
# https://github.com/projectcalico/calico/releases/latest/download/calicoctl-linux-arm64
# https://github.com/projectcalico/calico/releases/latest/download/calicoctl-linux-amd64
CALICO_YML="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml"
L_CALICO_YML="${DIRNAME}/${K8S_VERSION}/tigera-operator.yaml"
R_CALICO_YML="/tmp/tigera-operator.yaml"
CALICO_CUST_YML="https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml"
L_CALICO_CUST_YML="${DIRNAME}/${K8S_VERSION}/custom-resources.yaml"
R_CALICO_CUST_YML="/tmp/custom-resources.yaml"
# mirrors
# kubeadm config images list --kubernetes-version ${K8S_VERSION}
declare -A GCR_MAP=(
    [kube-apiserver:${K8S_VERSION}]=registry.k8s.io/kube-apiserver:${K8S_VERSION}
    [kube-scheduler:${K8S_VERSION}]=registry.k8s.io/kube-scheduler:${K8S_VERSION}
    [kube-proxy:${K8S_VERSION}]=registry.k8s.io/kube-proxy:${K8S_VERSION}
    [kube-controller-manager:${K8S_VERSION}]=registry.k8s.io/kube-controller-manager:${K8S_VERSION}
    [pause:3.9]=registry.k8s.io/pause:3.9
    [coredns:v1.10.1]=registry.k8s.io/coredns/coredns:v1.10.1
    [etcd:3.5.7-0]=registry.k8s.io/etcd:3.5.7-0
)
# #  kubelet v1.21.7
# declare -A GCR_MAP=(
#     [kube-apiserver:v1.21.7]=registry.k8s.io/kube-apiserver:v1.21.7
#     [kube-controller-manager:v1.21.7]=registry.k8s.io/kube-controller-manager:v1.21.7
#     [kube-scheduler:v1.21.7]=registry.k8s.io/kube-scheduler:v1.21.7
#     [kube-proxy:v1.21.7]=registry.k8s.io/kube-proxy:v1.21.7
#     [pause:3.4.1]=registry.k8s.io/pause:3.4.1
#     [etcd:3.4.13-0]=registry.k8s.io/etcd:3.4.13-0
#     [coredns:v1.8.0]=registry.k8s.io/coredns/coredns:v1.8.0
# )
GCR_MIRROR="registry.aliyuncs.com/google_containers"
##OPTION_END

print_predefine() {
    cat<<EOF
SSH_PORT        = ${SSH_PORT}
========================================
DASHBOARD_YML   = ${DASHBOARD_YML}
L_DASHBOARD_YML = ${L_DASHBOARD_YML}
R_DASHBOARD_YML = ${R_DASHBOARD_YML}
$(print_kv DASHBOARD_MAP)
========================================
FLANNEL_YML     = ${FLANNEL_YML}
L_FLANNEL_YML   = ${L_FLANNEL_YML}
R_FLANNEL_YML   = ${R_FLANNEL_YML}
$(print_kv FLANNEL_MAP)
========================================
INGRESS_YML     = ${INGRESS_YML}
L_INGRESS_YML   = ${L_INGRESS_YML}
R_INGRESS_YML   = ${R_INGRESS_YML}
$(print_kv INGRESS_MAP)
========================================
GCR_MIRROR      = ${GCR_MIRROR}
$(print_kv GCR_MAP)
EOF
    return 0
}
# pre defined ends
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
    local env_file=/etc/sysconfig/kubelet #centos
    #/etc/default/kubelet   #debian
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
        [ -e "${env_file}" ] && {
            echo "Centos based system"
            cat <<EOF | tee /etc/sysconfig/network-scripts/ifcfg-${bridge}
DEVICE="${bridge}"
ONBOOT="yes"
TYPE="Bridge"
BOOTPROTO="none"
STP="on"
            $(
                [ "${masq}" = true ] && {
                    echo "IPADDR=${gw}"
                    echo "PREFIX=${tmask}"
                }
            )
EOF
            cat <<EOF | tee /etc/sysconfig/network-scripts/route-${bridge}
            $(
                for i in "$@"; do
                    IFS=',' read -r x y <<< "${i}"
                    echo "$x via $y"
                done
            )
EOF
        } || {
            echo "Debian based system"
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

init_flannel_cni() {
    local pod_cidr=${1}
    local flannel_yml=${2}
    [ -e "${flannel_yml}" ] || return 1
    sed -i "s|\"Network\"\s*:\s*.*|\"Network\": \"${pod_cidr}\",|g" "${flannel_yml}"
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl apply -f "${flannel_yml}"
    # kubectl delete -f flannel.yml
    kubectl -n kube-system get configmaps kube-flannel-cfg -o yaml
    rm -f "${flannel_yml}"
}

init_calico_cni() {
    local svc_cidr=${1}
    local pod_cidr=${2}
    local calico_yml=${3}
    local calico_cust_yml=${4}
    [ -e "${calico_yml}" ] || [ -e "${calico_cust_yml}" ] || return 1
    # sed -i "s|replicas\s*:.*|replicas: ${TYPHA_REPLICAS:-1}|g" "${calico_typha_yml}"
    sed -i "s|cidr\s*:.*|cidr: ${pod_cidr}|g" "${calico_cust_yml}"
    # # IPIPCrossSubnet,IPIP,VXLAN,VXLANCrossSubnet,None
    # sed -i "s|encapsulation\s*:.*|encapsulation: ${crossnet_method}|g" "${calico_cust_yml}"
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl create -f "${calico_yml}"
    kubectl create -f "${calico_cust_yml}"
    kubectl -n kube-system get configmaps calico-config -o yaml || true
    rm -f "${calico_yml}" "${calico_cust_yml}" || true
    kubectl get nodes -o wide || true
    kubectl get pods --all-namespaces -o wide || true
}

init_ingress() {
    local ingress_yml=${1}
    [ -e "${ingress_yml}" ] || return 1
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl apply -f "${ingress_yml}"
    echo "remove: kubectl delete -f ..."
    rm -f "${ingress_yml}"
    # # wait ingress running & ready
    # kubectl wait --namespace ingress-nginx \
    #     --for=condition=ready pod \
    #     --selector=app.kubernetes.io/component=controller \
    #     --timeout=120s
}

init_dashboard() {
    local dashboard_yml=${1}
    # dashboard on master
    [ -e "${dashboard_yml}" ] || return 1
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl create -f "${dashboard_yml}"
    rm -f "${dashboard_yml}"
    kubectl get pods --namespace=kubernetes-dashboard
    # 修改service配置，将type: ClusterIP改成NodePort
    # kubectl edit service kubernetes-dashboard --namespace=kubernetes-dashboard
    kubectl get service kubernetes-dashboard --namespace=kubernetes-dashboard -o yaml | \
    sed 's/type:\s*[^ ]*$/type: NodePort/g' | \
    kubectl apply -f -
    kubectl -n kube-system create serviceaccount dashboard-admin
    kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
    kubectl -n kube-system describe secrets $(kubectl -n kube-system get secret | awk '/dashboard-admin/{print $1}') || true
    kubectl get service --namespace=kubernetes-dashboard
}

mirror_get_image() {
    local mirror="${1}"
    local mirror_img="${2}"
    local gcr_img="${3}"
    command -v ctr &> /dev/null && {
        ctr --namespace k8s.io image pull "${mirror}/${mirror_img}"
        ctr --namespace k8s.io image tag "${mirror}/${mirror_img}" "${gcr_img}"
        ctr --namespace k8s.io image rm "${mirror}/${mirror_img}"
        return 0
    }
    docker pull "${mirror}/${mirror_img}"
    docker tag "${mirror}/${mirror_img}" "${gcr_img}"
    docker rmi "${mirror}/${mirror_img}"
}
mirror_image_exist() {
    local tag=${1}
    command -v ctr &> /dev/null && {
        ctr --namespace k8s.io image ls | grep -q "${tag}" && return 0 || return 1
    }
    docker image ls | grep -q "${tag}" && return 0 || return 1
 }
mirror_load_image() {
    local tgz=${1}
    local tag=${2}
    command -v ctr &> /dev/null && {
        gunzip -c ${tgz} | ctr --namespace k8s.io image import - || true 2>/dev/null
        return 0
    }
    local imgid=$(gunzip -c ${tgz} | docker image load -q 2>/dev/null | sed -E "s/Loaded image( ID:|:)\s//g") || true
    docker tag ${imgid} ${tag} 2>/dev/null || true
}
mirror_save_image() {
    local img=${1}
    local tgz=${2}
    command -v ctr &> /dev/null && {
        ctr --namespace k8s.io image export - ${img} | gzip > ${tgz}
        return 0
    }
    docker save ${img} | gzip > ${tgz}
}
pre_conf_k8s_host() {
    local http_proxy=${1}
    local apiserver=${2}
    local pausekey=${3}
    via_proxy() {
        local http_proxy=${1}
        local dir=${2}
        [ -z ${http_proxy} ] && {
            rm -vfr ${dir}/http-proxy.conf || true
        } || {
            mkdir -vp ${dir}
            cat <<EOF > ${dir}/http-proxy.conf
[Service]
Environment=HTTP_PROXY=${http_proxy}
Environment=HTTPS_PROXY=${http_proxy}
Environment=NO_PROXY=${apiserver%:*},localhost,127.0.0.0/8
EOF
        }
    }
    pre_containerd_env() {
        local http_proxy=${1}
        local apiserver=${2}
        local pausekey=${3}
        # containerd proxy set in env when run ctr
        via_proxy "${http_proxy}" "/etc/systemd/system/containerd.service.d"
        # change sandbox_image on all nodes
        mkdir -vp /etc/containerd && containerd config default > /etc/containerd/config.toml || true
        sed -i -e "s/sandbox_image\s*=.*\/pause.*/sandbox_image = \"registry.k8s.io\/${pausekey}\"/g" /etc/containerd/config.toml
        # kubernets自v1.24.0后，就不再使用docker.shim，需要安装containerd(在docker基础下安装)
        sed -i 's/SystemdCgroup\s*=.*$/SystemdCgroup = true/g' /etc/containerd/config.toml
        # [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        #   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        #     endpoint = ["https://registry-1.docker.io"]
        # [plugins."io.containerd.grpc.v1.cri".registry.configs]
        #   [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
        #     insecure_skip_verify = true  #跳过认证
        #     ca_file = "/etc/containerd/certs.d/registry.harbor.com/ca.crt" #ca证书
        #     cert_file = "/etc/containerd/certs.d/registry.harbor.com/registry.harbor.com.cert" #harbor证书
        #     key_file = "/etc/containerd/certs.d/registry.harbor.com/registry.harbor.com.key" #密钥
        #   [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".auth]
        #     username = "admin"
        #     password = "pass12345"
        # [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        #   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."172.16.7.1:8888"]
        #     endpoint = ["http://172.16.7.1:8888"]
        #   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."k-registry.hb:8888"]
        #     endpoint = ["http://k-registry.hb:8888"]

        echo "ctr --namespace=k8s.io images push registry.harbor.com/test/app:latest --skip-verify --user admin:Harbor12345"
        echo "crictl pull registry.harbor.com/test/app:latest"
        # # containerd 忽略证书验证的配置
        #      [plugins."io.containerd.grpc.v1.cri".registry.configs]
        #        [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.0.12:8001".tls]
        #          insecure_skip_verify = true
        systemctl daemon-reload || true
        systemctl restart containerd.service || true
        systemctl enable containerd.service || true
    }
    pre_docker_env() {
        local http_proxy=${1}
        local apiserver=${2}
        via_proxy "${http_proxy}" "/etc/systemd/system/docker.service.d"
        mkdir -vp /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "http://hub-mirror.c.163.com"
  ],
  "insecure-registries": [
    "quay.io",
    "private.test.com"
  ],
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "data-root": "/var/lib/docker",
  "storage-driver": "overlay2",
  "iptables": false,
  "bridge": "none"
}
EOF
        systemctl daemon-reload || true
        systemctl restart docker.service || true
        systemctl enable docker.service || true
    }
    echo "127.0.0.1 localhost ${HOSTNAME:-$(hostname)}" > /etc/hosts
    touch /etc/resolv.conf || true #if /etc/resolv.conf non exists, k8s startup error
    swapoff -a
    sed -iE "/\sswap\s/d" /etc/fstab
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
    command -v ctr &> /dev/null && pre_containerd_env  "${http_proxy}" "${apiserver}" "${pausekey}" || pre_docker_env "${http_proxy}" "${apiserver}"
	systemctl enable kubelet.service
    systemctl disable firewalld --now || true
}

gen_k8s_join_cmds() {
    local version=${1}
    #kubeadm token list -o json
    local token=$(kubeadm token create)
    # kubeadm token create --print-join-command
    local sha_hash=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    # reupload certs
    local certs=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
    local api_srv=$(sed -n "s/\s*server:\s*\(.*\)/\1/p" /etc/kubernetes/kubelet.conf)
    echo kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash} --control-plane --certificate-key ${certs}
    echo kubeadm join ${api_srv} --token ${token} --discovery-token-ca-cert-hash sha256:${sha_hash}
}

modify_kube_proxy_ipvs() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl -n kube-system get configmaps kube-proxy -o yaml | \
    sed 's/mode:\s*"[^"]*"/mode: "ipvs"/g' | \
    kubectl apply -f -
    # kube-proxy ConfigMap, [mode=""] changed to [ipvs]
    kubectl -n kube-system delete pod -l k8s-app=kube-proxy
    # kubectl -n kube-system logs kube-proxy-tknk8
}

init_first_k8s_master() {
    local api_srv=${1} # apiserver dns-name:port
    local skip_proxy=${2}
    local version=${3}
    local pod_cidr=${4}
    local svc_cidr=${5}
    local opts="--control-plane-endpoint ${api_srv} --upload-certs ${pod_cidr:+--pod-network-cidr=${pod_cidr}} ${svc_cidr:+--service-cidr ${svc_cidr}} --apiserver-advertise-address=0.0.0.0"
    ${skip_proxy} && opts="--skip-phases=addon/kube-proxy ${opts}" 
    # kubeadm init --kubernetes-version ${version} phase addon kube-proxy
    # init kubeadm cluster on master
    kubeadm config images list --kubernetes-version ${version} || true
    kubeadm config print init-defaults || true
    echo "can modify 'imageRepository: registry.k8s.io', kubeadm config images list --config kubeadm-calico.conf"
    # kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version ${version}
    # kubeadm init --kubernetes-version ${version} phase --image-repository=registry.aliyuncs.com/google_containers --control-plane-endpoint "${api_srv}" --upload-certs
    kubeadm init --kubernetes-version ${version} ${opts}
    ##--apiserver-bind-port
    echo "FIX 'kubectl get cs' Unhealthy"
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-controller-manager.yaml
    sed -i "/^\s*-\s*--\s*port\s*=\s*0/d" /etc/kubernetes/manifests/kube-scheduler.yaml

    # # reupload certs
    # kubeadm init phase upload-certs --upload-certs
    #--apiserver-advertise-address=<ip-address-of-master-vm> #--service-cidr=10.1.0.0/16 --pod-network-cidr=172.16.0.0/16 
    # --control-plane-endpoint to set the shared endpoint for all control-plane nodes. Such an endpoint can be either a DNS name or an IP address of a load-balancer.
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" > /etc/profile.d/k8s.sh
    chmod 644 /etc/profile.d/k8s.sh
    export KUBECONFIG=/etc/kubernetes/admin.conf
    # # 使Master Node参与工作负载
    # kubectl taint nodes --all node-role.kubernetes.io/master-
    # # 禁止master部署pod</p> 
    # kubectl taint nodes k8s node-role.kubernetes.io/master=true:NoSchedule
    # # Pending check
    # kubectl -n kube-system describe pod coredns-7f6cbbb7b8-7phlt
    # kubectl describe node md1
    # kubectl get pods --all-namespaces
    # kubectl -n kube-system edit configmaps coredns -o yaml
    # kubectl -n kube-system delete pod coredns-7f6cbbb7b8-lfvxb
    # kubectl -n kube-system logs coredns-7f6cbbb7b8-vkj2l
    kubectl get pods --all-namespaces -o wide || true
    kubectl get nodes || true
    kubeadm token list || true
    # kubectl delete nodes md2
    # kubectl -n kube-system describe pod | grep IP
    echo "certificate expiration date"
    kubeadm certs check-expiration
    echo "renew certs: kubeadm certs renew all"
    # openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text |grep ' Not '
    echo "coredns replicas"
    kubectl -n kube-system get rs || true
    echo "kubectl -n kube-system scale --replicas=3 rs/coredns-XXXXXXX"
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
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "wget -q ${yml_url} -O ${remote_yml}"
        download ${ipaddr} "${SSH_PORT}" "root" "${remote_yml}" "${local_yml}"
    }
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
        ssh_func "root@${ipaddr}" "${SSH_PORT}" init_bridge_cni "${bridge}" "${subnet}" "${gw}" "${masq}" "${routes[@]}"
    done
}

init_kube_flannel_cni() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local flannel_cidr=${3}
    vinfo_msg <<EOF
"****** ${ipaddr} init flannel(${flannel_cidr}) cni.
  cidr=${flannel_cidr}
EOF
    prepare_flannel_images master worker
    ssh_func "root@${master[0]}" "${SSH_PORT}" init_flannel_cni "${flannel_cidr}" "${R_FLANNEL_YML}"
}

init_kube_calico_cni() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local pod_cidr=${3}
    local svc_cidr=${4}
    local ipaddr="${master[0]}"
    vinfo_msg <<EOF
****** ${ipaddr} init calico() cni svc: ${svc_cidr}, pod:${pod_cidr}.
EOF
    info_msg "calico need do, when NetworkManager present\n"
    cat <<EOF
# >/etc/NetworkManager/conf.d/calico.conf
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
EOF
    prepare_yml "${ipaddr}" "${L_CALICO_YML}" "${R_CALICO_YML}" "${CALICO_YML}"
    prepare_yml "${ipaddr}" "${L_CALICO_CUST_YML}" "${R_CALICO_CUST_YML}" "${CALICO_CUST_YML}"
    for ipaddr in $(array_print master) $(array_print worker); do
        prepare_k8s_images "${ipaddr}" CALICO_MAP "docker.io/calico"
        prepare_k8s_images "${ipaddr}" CALICO_OPER_MAP "quay.io/tigera"
    done
    ssh_func "root@${master[0]}" "${SSH_PORT}" init_calico_cni "${svc_cidr}" "${pod_cidr}" "${R_CALICO_YML}" "${R_CALICO_CUST_YML}"
}

prepare_k8s_images() {
    local ipaddr=${1}
    local img_map=${2}
    local mirror=${3}
    local img="" x="" y="" imgid=""
    cat <<EOF | vinfo3_msg
K8S_VERSION=${K8S_VERSION}
IPADDR=${ipaddr}
MIRROR=${mirror}
$(print_kv ${img_map})
EOF
    for img in $(array_print_label "${img_map}"); do
        file_exists "${DIRNAME}/${K8S_VERSION}/${img}.tar.gz" && {
            info_msg "Load ${img} for ${ipaddr}\n"
            ssh_func "root@${ipaddr}" "${SSH_PORT}" mirror_image_exist "$(array_get ${img_map} ${img})" && {
                info_msg "${mirror}/${img} exists [${K8S_VERSION}] LOCAL & ${ipaddr}, continue\n"
                continue
            }
            info_msg "${mirror}/${img} NOT exists ${ipaddr}, LOCAL upload\n"
            upload "${DIRNAME}/${K8S_VERSION}/${img}.tar.gz" ${ipaddr} "${SSH_PORT}" "root" "/tmp/${img}.tar.gz"
            ssh_func "root@${ipaddr}" "${SSH_PORT}" mirror_load_image "/tmp/${img}.tar.gz" "$(array_get ${img_map} ${img})"
            ssh_func "root@${ipaddr}" "${SSH_PORT}" "rm -f /tmp/${img}.tar.gz"
            continue
        }
        info_msg "Pull ${mirror}/${img} for ${ipaddr}\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" mirror_image_exist "$(array_get ${img_map} ${img})" || {
            info_msg "${mirror}/${img} NOT exists [${K8S_VERSION}] LOCAL ${ipaddr}, pull image\n"
            ssh_func "root@${ipaddr}" "${SSH_PORT}" mirror_get_image "${mirror}" "${img}" "$(array_get ${img_map} ${img})"
        }
        ssh_func "root@${ipaddr}" "${SSH_PORT}" mirror_save_image "$(array_get ${img_map} ${img})" "/tmp/${img}.tar.gz"
        download ${ipaddr} "${SSH_PORT}" "root" "/tmp/${img}.tar.gz" "${DIRNAME}/${K8S_VERSION}/${img}.tar.gz"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "rm -f /tmp/${img}.tar.gz"
    done
}

prepare_ingress_images() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local ipaddr="${master[0]}"
    # ingress yml should remove @sha256...... in image: sec!!
    prepare_yml "${ipaddr}" "${L_INGRESS_YML}" "${R_INGRESS_YML}" "${INGRESS_YML}"
    for ipaddr in $(array_print master) $(array_print worker); do
        prepare_k8s_images "${ipaddr}" INGRESS_MAP "${GCR_MIRROR}"
    done
}

prepare_flannel_images() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local ipaddr="${master[0]}"
    prepare_yml "${ipaddr}" "${L_FLANNEL_YML}" "${R_FLANNEL_YML}" "${FLANNEL_YML}"
    for ipaddr in $(array_print master) $(array_print worker); do
        prepare_k8s_images "${ipaddr}" FLANNEL_MAP "quay.io/coreos"
    done
    declare -A flannel_cni_map=(
        [mirrored-flannelcni-flannel-cni-plugin:v1.2]=rancher/mirrored-flannelcni-flannel-cni-plugin:v1.2
    )
    for ipaddr in $(array_print master) $(array_print worker); do
        prepare_k8s_images "${ipaddr}" flannel_cni_map "rancher"
    done
}

prepare_dashboard_images() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local ipaddr="${master[0]}"
    prepare_yml "${ipaddr}" "${L_DASHBOARD_YML}" "${R_DASHBOARD_YML}" "${DASHBOARD_YML}"
    for ipaddr in $(array_print master) $(array_print worker); do
        prepare_k8s_images "${ipaddr}" DASHBOARD_MAP "${GCR_MIRROR}"
    done
}

prepare_kube_images() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local ipaddr="" imgid=""
    # declare -A GCR_MAP=()
    # for imgid in $(ssh_func "root@${master[0]}" "${SSH_PORT}" "kubeadm config images list 2>/dev/null"); do
    #     GCR_MAP[$(basename ${imgid})]="${imgid}"
    # done
    for ipaddr in $(array_print master) $(array_print worker); do
        prepare_k8s_images "${ipaddr}" GCR_MAP "${GCR_MIRROR}"
    done
}

init_kube_cluster() {
    local master=($(array_print ${1}))
    local worker=($(array_print ${2}))
    local api_srv=${3}
    local pod_cidr=${4}
    local skip_proxy=${5}
    local svc_cidr=${6}
    [ "$(array_size master)" -gt "0" ] || return 1
    local ipaddr=$(array_get master 0)
    info_msg "****** ${ipaddr} init first master(${api_srv})\n"
    IFS=':' read -r tname tport <<< "${api_srv}"
    local hosts="${ipaddr} ${tname}"
    ssh_func "root@${ipaddr}" "${SSH_PORT}" "echo ${hosts} >> /etc/hosts"
    ssh_func "root@${ipaddr}" "${SSH_PORT}" init_first_k8s_master "${api_srv}" "${skip_proxy}" "${K8S_VERSION}" "${pod_cidr}" "${svc_cidr}"
    #kubeadm token list -o json
    local token=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "kubeadm token create")
    # kubeadm token create --print-join-command
    local sha_hash=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")
    # reupload certs
    local certs=$(ssh_func "root@${ipaddr}" "${SSH_PORT}" "kubeadm init phase upload-certs --upload-certs | tail -n 1")
    for ((i=1;i<$(array_size master);i++)); do
        ipaddr=$(array_get master ${i})
        info1_msg "****** ${ipaddr} add master(${api_srv})\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "echo ${hosts} >> /etc/hosts"
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
            HTTP_PROXY      default ''
            K8S_VERSION     default v1.27.3
        --apiserver            <str>  k8s cluster api-server-endpoint
                                      default "k8sapi.local.com:6443"
                                      k8sapi.local.com is first master node, store in /etc/hosts(all masters&workers)
                                      u should make a loadbalance to all masters later,
        -m|--master   *        <ip>   master nodes, support multi nodes
        -w|--worker            <ip>   worker nodes, support multi nodes
        -s|--svc_cidr          <cidr> servie cidr, default 10.96.0.0/12
        --bridge               <str>  k8s bridge_cni, bridge name
        --calico               <cidr> calico cni, pod_cidr
        --flannel              <cidr> k8s flannel_cni, pod_cidr
                                      skip_proxy flannel_cni no work. get info etcd with service_cluster_ip
        --dashboard                   install dashboard, default false
        --skip_proxy                  skip install kube-proxy, default false
        --ipvs                        kube-proxy mode ipvs, default false
        --ingress                     install ingress, default false
        --teardown             <ip>   remove all k8s config
        --password             <str>  ssh password(default use sshkey)
        pre define file, see
                ##OPTION_START
                ...........
                ###OPTION_END
                use: kubeadm config images list
                        registry.k8s.io/kube-apiserver:v1.27.3
                        registry.k8s.io/kube-controller-manager:v1.27.3
                        registry.k8s.io/kube-scheduler:v1.27.3
                        registry.k8s.io/kube-proxy:v1.27.3
                        registry.k8s.io/pause:3.9
                        registry.k8s.io/etcd:3.5.7-0
                        registry.k8s.io/coredns/coredns:v1.10.1
        --gen_join_cmds               only generate join commands
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    Example:
        ${SCRIPTNAME} --master 192.168.168.150 --worker 192.168.168.151 --worker 192.168.168.152 --svc_cidr 172.16.200.0/24 --calico 172.16.100.0/24 --ipvs
        MASQ=false, the gateway is outside, else gateway is bridge(cn0)
        Debian instll containerd:(newer k8s:v1.20+ use containerd instead docker-ce)
            apt -y install containerd containernetworking-plugins containers-storage conntrack-tools containernetworking-plugins socat
        Debian install docker:
            apt -y install wget curl apt-transport-https ca-certificates ethtool socat bridge-utils ipvsadm ipset jq
            repo=docker
            apt -y install gnupg && wget -q -O- 'http://mirrors.aliyun.com/docker-ce/linux/debian/gpg' | \
                gpg --dearmor > /etc/apt/trusted.gpg.d/\${repo}-archive-keyring.gpg
            echo "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/debian \$(sed -n "s/^\s*VERSION_CODENAME\s*=\s*\(.*\)/\1/p" /etc/os-release) stable" > /etc/apt/sources.list.d/\${repo}.list
            apt update && apt -y install docker-ce
        Debian install k8s:
            wget -q -O- http://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
            echo "deb http://mirrors.aliyun.com/kubernetes/apt kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
            apt update && apt -y install kubelet kubectl kubeadm
        Centos install containerd
            yum -y install containerd containernetworking-plugins conntrack-tools containernetworking-plugins socat
        Centos install docker & k8s
            yum -y install wget curl ethtool socat bridge-utils
            wget http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -O /etc/yum.repos.d/docker-ce.repo
            sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
            yum -y install docker-ce
            cat > /etc/yum.repos.d/kubernetes.repo <<EOFREPO
            [kubernetes]
            name=Kubernetes
            baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
            enabled=1
            gpgcheck=0
            EOFREPO
            yum -y install kubelet kubeadm kubectl
EOF
    exit 1
}

main() {
    local master=() worker=() teardown=() bridge="" apiserver="k8sapi.local.com:6443" gen_join_cmds=""
    local flannel_cidr="" dashboard=false ipvs=false ingress=false skip_proxy=false calico_cidr="" svc_cidr=""
    local opt_short="m:w:s:"
    local opt_long="password:,gen_join_cmds,apiserver:,master:,worker:,bridge:,flannel:,calico:,dashboard,ipvs,ingress,teardown:,svc_cidr:,"
    opt_long+="skip_proxy,"
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
            -s | --svc_cidr)shift; svc_cidr=${1}; shift;;
            --bridge)       shift; bridge=${1}; shift;;
            --flannel)      shift; flannel_cidr=${1}; shift;;
            --calico)       shift; calico_cidr=${1}; shift;;
            --dashboard)    shift; dashboard=true;;
            --ingress)      shift; ingress=true;;
            --skip_proxy)   shift; skip_proxy=true;;
            --ipvs)         shift; ipvs=true;;
            --teardown)     shift; teardown+=(${1}); shift;;
            --password)     shift; set_sshpass "${1}"; shift;;
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
    for ipaddr in "${teardown[@]}"; do
        info_msg "${ipaddr} teardown all k8s config!\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "teardown"
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    [ "$(array_size master)" -gt "0" ] || usage "at least one master"
    [ -z "${gen_join_cmds}" ] || {
        ssh_func "root@${master[0]}" "${SSH_PORT}" gen_k8s_join_cmds ${K8S_VERSION} 2>/dev/null
        info_msg "GEN_CMDS OK\n"
        return 0
    }
    [ -z "${bridge}" ] && [ -z "${flannel_cidr}" ] && [ -z "${calico_cidr}" ] && usage "network cni bridge/flannel/calico"
    [ -e ${DIRNAME}/define.conf ] || sed -n '/^##OPTION_START/,/^##OPTION_END/p' ${SCRIPTNAME} > ${DIRNAME}/define.conf
    ${EDITOR:-vi} ${DIRNAME}/define.conf || true
    source ${DIRNAME}/define.conf || true
    print_predefine
    confirm "Confirm NEW init k8s env(timeout 10,default N)?" 10 || exit_msg "BYE!\n"
    mkdir -vp "${DIRNAME}/${K8S_VERSION}"
    for ipaddr in $(array_print master) $(array_print worker); do
        info_msg "****** ${ipaddr} pre valid host env\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" pre_conf_k8s_host "${HTTP_PROXY}" "${apiserver}" "$(array_print_label GCR_MAP  | grep 'pause')"
    done
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
        info_msg "install bridge_cni end(${bridge})\n"
    }
    local pod_cidr=""
    [ -z "${flannel_cidr}" ] || pod_cidr=${calico_cidr}
    [ -z "${calico_cidr}" ] || pod_cidr=${calico_cidr}
    init_kube_cluster master worker "${apiserver}" "${pod_cidr}" "${skip_proxy}" "${svc_cidr}"
    ${skip_proxy} || ${ipvs} && ssh_func "root@${master[0]}" "${SSH_PORT}" modify_kube_proxy_ipvs
    [ -z "${calico_cidr}" ] || {
        info_msg "install calico cni begin\n"
        init_kube_calico_cni master worker "${calico_cidr}" "${svc_cidr}"
        info_msg "install calico cni end\n"
    }
    [ -z "${flannel_cidr}" ] || {
        info_msg "install flannel_cni begin\n"
        init_kube_flannel_cni master worker "${flannel_cidr}"
        info_msg "install flannel_cni end\n"
    }
    ${ingress} && {
        prepare_ingress_images master worker
        ssh_func "root@${master[0]}" "${SSH_PORT}" init_ingress "${R_INGRESS_YML}"
    }
    ${dashboard} && {
        prepare_dashboard_images master worker
        ssh_func "root@${master[0]}" "${SSH_PORT}" init_dashboard "${R_DASHBOARD_YML}"
    }
    info_msg "export k8s configuration"
    ssh_func "root@${master[0]}" "${SSH_PORT}" 'kubeadm config print init-defaults'
    ssh_func "root@${master[0]}" "${SSH_PORT}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl cluster-info"
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
    info_msg "diag: kubectl -n kube-system edit configmaps kube-proxy -o yaml\n"
    info_msg "diag: kubectl -n kube-system exec -it etcd-node-xxxx -- /bin/sh\n"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
