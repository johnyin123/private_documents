#!/bin/echo Warnning, this library must only be sourced!
VERSION+=("1c3a848[2023-07-06T20:44:14+08:00]:virt_gatter_info.sh")
################################################################################
__dummy_dryrun() {
    export arch=aarch64
    export uefi=""
    export net=()
    export -A pool=()
    return 0 
}
__virsh_wrap() {
    local host="${1}"
    local port="${2}"
    local user="${3}"
    shift 3;
    virsh -q ${host:+-c qemu+ssh://${user:+${user}@}${host}${port:+:${port}}/system} $@
}
# source ${DIRNAME}/gatter.sh ${host:+-h ${host}} ${port:+-u ${port}} ${user:+-u ${user}} ${DRYRUN:+-d} || exit_msg "pre gatter error\n"
# echo $arch $uefi
# array_print net
# array_print pool
__main() {
    local host="" port="" user=""
    local opt_short="h:p:u:d"
    local opt_long="host:,port:,user:,dryrun"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -h | --host)      shift; host=${1}; shift;;
            -p | --port)      shift; port=${1}; shift;;
            -u | --user)      shift; user=${1}; shift;;
            ########################################
            -d | --dryrun)    shift; __dummy_dryrun; return 0;;
            --)               shift; break;;
        esac
    done
    local xml=$(__virsh_wrap "${host}" "${port}" "${user}" domcapabilities) || return 1
    export arch=$(printf "${xml}" | xmlstarlet sel -t -v "domainCapabilities/arch") || return 2
    export uefi=$(printf "${xml}" | xmlstarlet sel -t -v "domainCapabilities/os/loader/value") || return 3
    export net=()
    declare -g -A pool=()

    for item in $(__virsh_wrap "${host}" "${port}" "${user}" net-list --name); do
        net+=(${item})
    done
    for item in $(__virsh_wrap "${host}" "${port}" "${user}" pool-list --all --name); do
        pool[${item}]=$(__virsh_wrap "${host}" "${port}" "${user}" pool-dumpxml ${item})
    done
    return 0
}
__main "$@"
