#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("54d9886[2023-07-28T10:01:11+08:00]:kubesphere.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
init_kubesphere() {
    local ks_cluster_yaml=${1}
    local ks_installer_yaml=${2}
    local registry=${3}
    local ks_installer=${4}
    sed -i "s|local_registry\s*:\s*.*|local_registry: ${registry}|g" "${ks_cluster_yaml}"
    # enable redis
    sed -i "/redis\s*:$/{n; s/enabled\s*:.*/enabled: true/;}" "${ks_cluster_yaml}"
    sed -i "s|image\s*:\s*.*ks-installer.*|image: ${ks_installer}|g" "${ks_installer_yaml}"
    kubectl apply -f "${ks_installer_yaml}"
    kubectl apply -f "${ks_cluster_yaml}"
    rm -f "${ks_cluster_yaml}" "${ks_installer_yaml}"
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
        -r|--registry    *  <str>   private registry, for install kubesphere
                                    exam: registry.local:5000
        -i|--installer   *  <str>   ks-installer image image
                                    exam: registry.local/kubesphere/ks-installer:v3.2.1
        -U|--user           <user>  master ssh user, default root
        -P|--port           <int>   master ssh port, default 60022
        --sshpass           <str>   master ssh password, default use keyauth
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        prepare sotrageclass(default)
        prepare image: https://github.com/kubesphere/ks-installer/releases/download/v3.2.1/images-list.txt
EOF
    exit 1
}
main() {
    local master="" user="root" port=60022 registry="" installer=""
    local opt_short="m:r:i:U:P:"
    local opt_long="master:,registry:,installer:,user:,port:,sshpass:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)    shift; master=${1}; shift;;
            -r | --registry)  shift; registry=${1}; shift;;
            -i | --installer) shift; installer=${1}; shift;;
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
    [ -z "${registry}" ] || [ -z "${installer}" ] || [ -z "${master}" ] && usage "master/registry/ks_installer must input"
    file_exists cluster-configuration.yaml && file_exists kubesphere-installer.yaml || {
        cat<<'EOF'
https://kubernetes-helm.pek3b.qingstor.com/linux-${ARCH}/${HELM_VERSION}/helm
https://github.com/kubesphere/ks-installer/releases/download/${KS_VER}/kubesphere-installer.yaml
https://github.com/kubesphere/ks-installer/releases/download/${KS_VER}/cluster-configuration.yaml
EOF
        exit_msg "download files and retry\n"
    }
    upload "cluster-configuration.yaml" "${master}" "${port}" "${user}" "/tmp/cluster-configuration.yaml"
    upload "kubesphere-installer.yaml" "${master}" "${port}" "${user}" "/tmp/kubesphere-installer.yaml"
    vinfo_msg <<EOF
registry:  ${registry}
installer: ${installer}
EOF
    ssh_func "${user}@${master}" "${port}" init_kubesphere "/tmp/cluster-configuration.yaml" "/tmp/kubesphere-installer.yaml" "${registry}" "${installer}"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
