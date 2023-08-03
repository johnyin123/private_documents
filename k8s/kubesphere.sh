#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("f4cecb3[2023-08-03T16:41:07+08:00]:kubesphere.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
SSH_PORT=${SSH_PORT:-60022}

KS_INSTALLER_YML="https://github.com/kubesphere/ks-installer/releases/download/v3.3.2/kubesphere-installer.yaml"
L_KS_INSTALLER_YML=kubesphere-installer.yaml
R_KS_INSTALLER_YML=/tmp/kubesphere-installer.yaml

CLUSTER_CONF_YML="https://github.com/kubesphere/ks-installer/releases/download/v3.3.2/cluster-configuration.yaml"
L_CLUSTER_CONF_YML=cluster-configuration.yaml
R_CLUSTER_CONF_YML=/tmp/cluster-configuration.yaml

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
    local master="" registry="" installer=""
    local opt_short="m:r:i:"
    local opt_long="master:,registry:,installer:,password:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)    shift; master=${1}; shift;;
            -r | --registry)  shift; registry=${1}; shift;;
            -i | --installer) shift; installer=${1}; shift;;
            --password)       shift; set_sshpass "${1}"; shift;;
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
    file_exists "${L_KS_INSTALLER_YML}" && \
        file_exists "${L_CLUSTER_CONF_YML}" || \
        confirm "${L_KS_INSTALLER_YML}/${L_CLUSTER_CONF_YML} not exists, continue? (timeout 10,default N)?" 10 || exit_msg "BYE!\n"
    prepare_yml "${master}" "${L_CLUSTER_CONF_YML}" "${R_CLUSTER_CONF_YML}" "${CLUSTER_CONF_YML}"
    prepare_yml "${master}" "${L_KS_INSTALLER_YML}" "${R_KS_INSTALLER_YML}" "${KS_INSTALLER_YML}"
    vinfo_msg <<EOF
registry:  ${registry}
installer: ${installer}
EOF
    ssh_func "root@${master}" "${SSH_PORT}" init_kubesphere "${R_CLUSTER_CONF_YML}" "${R_KS_INSTALLER_YML}" "${registry}" "${installer}"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
