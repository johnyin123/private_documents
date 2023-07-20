#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("505ec4e[2023-07-14T10:35:33+08:00]:virt_createvol.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -K|--kvmhost     <ipaddr>  kvm host address
        -U|--kvmuser     <str>     kvm host ssh user
        -P|--kvmport     <int>     kvm host ssh port
        --kvmpass        <password>kvm host ssh password
        -p|--pool    *   <str>      libvirt store pool name
        -n|--name    *   <str>      vol name
        -f|--fmt         <str>      default raw, qemu-img format
        -s|--size    *   <size>     size, GiB/MiB
        -b|--backing_vol <str>
        -F|--backing_fmt <str>
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    cat <<EOVOL | virsh vol-create --pool default --file /dev/stdin
<volume>
 <name>test.img</name>
 <capacity unit="G">1</capacity>
</volume>
EOVOL
    virsh vol-path --pool default test.img
EOF
    exit 1
}
main() {
    local kvmhost="" kvmuser="" kvmport="" kvmpass=""
    local pool="" name="" fmt="raw" size="" backing_vol="" backing_fmt=""
    local opt_short="K:U:P:p:f:n:s:b:F:"
    local opt_long="kvmhost:,kvmuser:,kvmport:,kvmpass:,pool:,fmt:,name:,size:,backing_vol:,backing_fmt:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -K | --kvmhost) shift; kvmhost=${1}; shift;;
            -U | --kvmuser) shift; kvmuser=${1}; shift;;
            -P | --kvmport) shift; kvmport=${1}; shift;;
            --kvmpass)      shift; kvmpass=${1}; shift;;
            -p | --pool)          shift; pool=${1}; shift;;
            -n | --name)          shift; name=${1}; shift;;
            -f | --fmt)           shift; fmt=${1}; shift;;
            -s | --size)          shift; size=${1}; shift;;
            -b | --backing_vol)   shift; backing_vol=${1}; shift;;
            -F | --backing_fmt)   shift; backing_fmt=${1}; shift;;
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
    [ ! -z "${pool}" ] && [ ! -z "${name}" ] && [ ! -z "${size}" ] || usage "pool/name/size must input"
    [ -z ${kvmpass} ]  || set_sshpass "${kvmpass}"
    info_msg "create vol ${name} on ${pool} size ${size}\n"
    virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" pool-start ${pool} &>/dev/null || true
    virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" pool-refresh ${pool} || exit_msg "pool-refresh error\n"
    virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" vol-create-as --pool ${pool} --name ${name} --capacity 1M --format ${fmt} \
        ${backing_vol:+--backing-vol ${backing_vol} --backing-vol-format ${backing_fmt} } || exit_msg "vol-create-as error\n"
    virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" vol-resize --pool ${pool} --vol ${name} --capacity ${size} || exit_msg "vol-resize error\n"
    local val=$(virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" vol-path --pool "${pool}" "${name}") || error_msg "vol-path error\n"
    info_msg "create ${val} OK\n"
    return 0
}
main "$@"
