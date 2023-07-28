#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("568481c[2023-07-28T14:03:06+08:00]:inst_openebs.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
init_openebs() {
    local yaml=${1}
    local registry=${2}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "modify image registry"
    sed -i "s|image\s*:\s*openebs|image: ${registry}/openebs|g" "${yaml}"
    kubectl apply -f "${yaml}"
    rm -f "${yaml}"
}
init_mayastor() {
    cat<<EOF
helm repo add mayastor https://openebs.github.io/mayastor-extensions/
helm search repo mayastor --versions
helm install mayastor mayastor/mayastor -n mayastor --create-namespace --version 2.3.0 --debug --insecure-skip-tls-verify
kubectl get pods -n mayastor
EOF
    local sc_name=${1}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "diskpool define"
    cat <<EOF | kubectl apply -f -
apiVersion: openebs.io/v1alpha1
kind: DiskPool
metadata:
  name: pool-on-node-1
  namespace: mayastor
spec:
  node: workernode-1-hostname
  disks: ["/dev/disk/by-uuid/<uuid>"]
EOF
    echo "verify .."
    kubectl get dsp -n mayastor
    echo "create mayastor storageclass"
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${sc_name}
parameters:
  ioTimeout: "30"
  protocol: nvmf
  repl: "1"
provisioner: io.openebs.csi-mayastor
EOF
    kubectl get sc -n mayastor
    echo "define pvc"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-${sc_name}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: ${sc_name}
EOF
    kubectl get pvc pvc-${sc_name}
    # verify plugin installed
    kubectl mayastor -V  &>/dev/null && kubectl mayastor get volumes
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
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -m|--master      *  <ip>    master ipaddr
        -r|--registry    *  <str>   private registry, for install openebs
                                    exam: registry.local:5000
        -U | --user         <user>  master ssh user, default root
        -P | --port         <int>   master ssh port, default 60022
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
    local master="" user="root" port=60022 registry=""
    local opt_short="m:r:U:P:"
    local opt_long="master:,registry:,user:,port:,sshpass:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)    shift; master=${1}; shift;;
            -r | --registry)  shift; registry=${1}; shift;;
            -U | --user)      shift; user=${1}; shift;;
            -P | --port)      shift; port=${1}; shift;;
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
    [ -z "${registry}" ] || [ -z "${master}" ] && usage "master/registry must input"
    file_exists openebs-operator.yaml || {
        cat<<'EOF'
https://openebs.github.io/charts/openebs-operator.yaml
EOF
        exit_msg "download files and retry\n"
    }
    upload "openebs-operator.yaml" "${master}" "${port}" "${user}" "/tmp/openebs-operator.yaml"
    ssh_func "${user}@${master}" "${port}" init_openebs "/tmp/openebs-operator.yaml" "${registry}"
    info_msg "diag: kubectl get felixconfiguration -o yaml\n"
    info_msg "ALL DONE\n" 
    return 0
}
main "$@"
