#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2023-02-01T10:05:42+08:00]:keepalived_lvs.sh")
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -v|--vip)  * <ipaddr> virtual ipaddr 192.168.168.2
        -r|--rip)  * <ipaddr> real ipaddr support multi input
        -V|--version
        -h|--help help
EOF
    exit 1
}
main() {
    local vip=""
    local rip=()
    local opt_short="v:r:"
    local opt_long="vip:,rip:,"
    opt_short+="Vh"
    opt_long+="version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -v | --vip)     shift; vip=${1}; shift;;
            -r | --rip)     shift; rip+=(${1}); shift;;
            ########################################
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${vip}" ] || ((${#rip[@]} == 0)) || {
        cat <<EOF
global_defs {
   router_id LVS1
}

virtual_server ${vip} 0 {
    delay_loop 2
    lb_algo rr
    lb_kind DR
    persistence_timeout 360
    protocol TCP

$(for real in ${rip[@]}; do
cat<<EO_REAL
    real_server ${real} 0 {
        weight 1
        PING_CHECK {
            retry 2
        }
    }
EO_REAL
done)
}

virtual_server ${vip} 0 {
    delay_loop 2
    lb_algo rr
    lb_kind DR
    persistence_timeout 360
    protocol UDP

$(for real in ${rip[@]}; do
cat<<EO_REAL
    real_server ${real} 0 {
        weight 1
        PING_CHECK {
            retry 2
        }
    }
EO_REAL
done)
}
EOF
    }
    return 0
}
main "$@"
