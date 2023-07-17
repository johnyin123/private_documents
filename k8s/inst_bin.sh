#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("569e35f[2023-07-17T14:27:08+08:00]:inst_bin.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
SSH_PORT=${SSH_PORT:-60022}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
            SSH_PORT        default 60022
        -v|--ver    *  <k8s version>
        -a|--arch      <arch>         default amd64
        --ipaddr       <ipaddress>    remote server for install k8s service, via ssh
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    latest version: curl -L -s https://dl.k8s.io/release/stable.txt
    cri-tools kubernetes-cni
EOF
    exit 1
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
main() {
    local ver="" arch=amd64 ipaddr=""
    local opt_short="v:a:"
    local opt_long="ver:,arch:,ipaddr:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -v | --ver)          shift; ver=${1}; shift;;
            -a | --arch)         shift; arch=${1}; shift;;
            --ipaddr)            shift; ipaddr=${1}; shift;;
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
    [ -z ${ver} ] && usage "ver must input"
    [ -z "${ipaddr}" ] && return 0
    file_exists "kubelet.${ver}.${arch}" && info_msg "kubelet.${ver}.${arch} exists.\n" || fetch https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubelet kubelet.${ver}.${arch}
    file_exists "kubeadm.${ver}.${arch}" && info_msg "kubeadm.${ver}.${arch} exists.\n" || fetch https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubeadm kubeadm.${ver}.${arch}
    file_exists "kubectl.${ver}.${arch}" && info_msg "kubectl.${ver}.${arch} exists.\n" || fetch https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl kubectl.${ver}.${arch}
    file_exists "crictl.${arch}" && info_msg "crictl.${arch} exists.\n" || {
        echo "https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.27.1/crictl-v1.27.1-linux-arm.tar.gz"
        echo "https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.27.1/crictl-v1.27.1-linux-amd64.tar.gz"
        exit_msg "download crictl, add crictl.${arch}, retry\n"
    }
    file_exists "calicoctl-linux-${arch}" && info_msg "calicoctl-linux-${arch} exists.\n"
    upload "kubelet.${ver}.${arch}" "${ipaddr}" "${SSH_PORT}" "root" "/usr/bin/kubelet" 
    upload "kubeadm.${ver}.${arch}" "${ipaddr}" "${SSH_PORT}" "root" "/usr/bin/kubeadm"
    upload "kubectl.${ver}.${arch}" "${ipaddr}" "${SSH_PORT}" "root" "/usr/bin/kubectl"
    upload "calicoctl-linux-${arch}" "${ipaddr}" "${SSH_PORT}" "root" "/usr/bin/calicoctl"
    ssh_func "root@${ipaddr}" "${SSH_PORT}" "chmod 755 /usr/bin/kubelet /usr/bin/kubeadm /usr/bin/kubectl /usr/bin/calicoctl || true"
    ssh_func "root@${ipaddr}" "${SSH_PORT}" "mkdir -p /etc/systemd/system/kubelet.service.d/ /etc/kubernetes/ /var/lib/kubelet"
    cat <<'EOF' > 10-kubeadm.conf 
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
    upload "10-kubeadm.conf" "${ipaddr}" "${SSH_PORT}" "root" "/etc/systemd/system/kubelet.service.d/10-kubeadm.conf"
    cat <<'EOF' > kubelet.service 
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    upload "kubelet.service " "${ipaddr}" "${SSH_PORT}" "root" "/lib/systemd/system/kubelet.service"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"

