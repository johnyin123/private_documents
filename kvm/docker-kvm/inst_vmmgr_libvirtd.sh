#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("initver[2025-04-17T11:06:58+08:00]:inst_vmmgr_libvirtd.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -t|--target   * <str>    target directory for libvirtd data & conf
        -u|--user    <username>  username for ssh login(used for upload images)
                                 local storage defined, image tpl upload via this user
                                 default root
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
check_depends() {
    local files=(server-cert.pem server-key.pem ca-cert.pem id_rsa.pub)
    local cmds=(socat docker)
    log "file(${files[@]})"
    for fn in ${files[@]}; do
        [ -e "${fn}" ] || { log "${fn} file, nofound"; exit 1;}
    done
    log "cmd(${cmds[@]})"
    for cmd in ${cmds[@]}; do
        command -v "${cmd}" &> /dev/null || { log "${cmd} nofound"; exit 1;}
    done
}
make_libvirtd_tree() {
    local target="${1}"
    local uid="${2}"
    local gid="${3}"
    local home_dir="${4}"
    for dir in log vms pki secrets run/libvirt lib/libvirt; do
        install -v -d -m 0755 "${target}/${dir}"
    done
    log "install PKI"
    openssl x509 -text -noout -in server-cert.pem | grep -E 'DNS|Before|After' | sed 's/^\s*//g'
    install -v -C -m 0440 ca-cert.pem     ${target}/pki/ca-cert.pem
    install -v -C -m 0440 server-key.pem  ${target}/pki/server-key.pem
    install -v -C -m 0440 server-cert.pem ${target}/pki/server-cert.pem
    log "install SSH key for mgr-api" && install -v -d -m 0700 --group=${gid} --owner=${uid} ${home_dir}/.ssh && {
        install --backup -v -C -m 0600 --group=${gid} --owner=${uid} id_rsa.pub ${home_dir}/.ssh/authorized_keys
    }
}
main() {
    local target="" user="root"
    local opt_short="t:u:"
    local opt_long="target:,user:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -t | --target)  shift; target=${1}; shift;;
            -u | --user)    shift; user=${1}; shift;;
            ########################################
            -q | --quiet)   shift; FILTER_CMD=;;
            -l | --log)     shift; LOGFILE=${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ "$(id -u)" -eq 0 ] || { log "root need!"; exit 1; }
    exec > >(${FILTER_CMD:-sed '/^\s*#/d'} | tee ${LOGFILE:+-i ${LOGFILE}})
    [ -z "${target}" ] && usage "target dir must input"
    [ -d "${target}" ] && { log "${target} directory exist!!!"; exit 2; }
    local USR_ID=$(id -u ${user})
    local GRP_ID=$(id -g ${user})
    local USR_NAME=$(id -un ${user})
    local USR_HOME=$(getent passwd ${user} | cut -d: -f6)
    check_depends
    make_libvirtd_tree "${target}" "${USR_ID}" "${GRP_ID}" "${USR_HOME}"
    cat <<EODOC
# make local pool dir /storage
# # mkdir /storage
docker create --name libvirtd \\
    --network host \\
    --restart always \\
    --privileged \\
    --device /dev/kvm \\
    -v ${target}/log:/var/log/libvirt \\
    -v ${target}/vms:/etc/libvirt/qemu \\
    -v ${target}/pki:/etc/libvirt/pki \\
    -v ${target}/secrets:/etc/libvirt/secrets \\
    -v ${target}/run/libvirt:/var/run/libvirt \\
    -v ${target}/lib/libvirt:/var/lib/libvirt \\
    -v /storage:/storage \\
    registry.local/libvirtd/kvm:bookworm
EODOC
    return 0
}
main "$@"
