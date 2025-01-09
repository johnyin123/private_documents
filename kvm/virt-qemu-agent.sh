#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("f373764[2025-01-09T13:23:16+08:00]:virt-qemu-agent.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
VIRSH_OPT="-k 300 -K 5 -q"
#ControlMaster auto
#ControlPath  ~/.ssh/sockets/%r@%h-%p

fake_virsh() {
    local usr_srv_port=$1;shift 1
    try virsh -c qemu+ssh://${usr_srv_port}/system ${VIRSH_OPT} ${*}
}

inject_pubkey() {
    local usr_srv_port=$1;shift 1
    local domain=$1;shift 1

    # mkdir /root/.ssh
    fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} '{"execute":"guest-exec","arguments":{"path":"mkdir","arg":["-p","/root/.ssh"],"capture-output":true}}'
    # # 假设上一步返回{"return":{"pid":911}}，接下来查看结果（通常可忽略）
    # '{"execute":"guest-exec-status","arguments":{"pid":911}}'
    # chmod 700 /root/.ssh
    fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} '{"execute":"guest-exec","arguments":{"path":"chmod","arg":["700","/root/.ssh"],"capture-output":true}}'
    # # 假设上一步返回{"return":{"pid":912}}，接下来查看结果（通常可忽略）
    # '{"execute":"guest-exec-status","arguments":{"pid":912}}'

    # touch /root/.ssh/authorized_keys
    fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} '{"execute":"guest-exec","arguments":{"path":"touch","arg":["/root/.ssh/authorized_keys"],"capture-output":true}}'
    # # 假设上一步返回{"return":{"pid":913}}，接下来查看结果（通常可忽略）
    # '{"execute":"guest-exec-status","arguments":{"pid":913}}'

    # chmod 600 /root/.ssh/authorized_keys
    fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} '{"execute":"guest-exec","arguments":{"path":"chmod","arg":["600","/root/.ssh/authorized_keys"],"capture-output":true}}'
    # # 假设上一步返回{"return":{"pid":914}}，接下来查看结果（通常可忽略）
    # '{"execute":"guest-exec-status","arguments":{"pid":914}}'

    # 打开文件（以读写方式打开），获得句柄
    out=$(fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} '{"execute":"guest-file-open", "arguments":{"path":"/root/.ssh/authorized_keys","mode":"w+"}}')
    local handle=$(printf "%s" $out | jq -c ".return")
    # 写文件，假设上一步返回{"return":1000}，1000就是句柄
    # cat ~/.ssh/id_rsa.pub | base64 -w 0
    fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} "{\"execute\":\"guest-file-write\", \"arguments\":{\"handle\":${handle},\"buf-b64\":\"c3NoLXJzYSBBQUFBQjNOemFDMXljMkVBQUFBREFRQUJBQUFCQVFES3hkcmlpQ3FiemxLV1pnVzVKR0Y2eUpuU3lWdHViRUFXMTdtb2syenNRN2FsMmNSWWdHako1aUZTdlpIenozYXQ3UXBOcFJrYWZhdUgvRGZyWnozeUdLa1VJYk9iMFVhdkNINWFlbE5kdVhhQnQ3ZFkyT1JIaWJPc1N2VFhBaWZHd3RMWTY3VzRWeVUvUkJuQ0M3eDNIeFVCNkJRRjZxd3pDR3dyeS9sckJENkZaenQ3dExqZnhjYkxoc256cU9HMnk3Nm40SDU0UnJvb0duMWlYSEJEQlhmdk1SN25vWktielhBVVF5T3g5bTA3Q3FobnBncE1sR0ZMN3NoVWRsRlBOTFBaZjVKTHNFczkwaDNkODg1T1dSeDlLcCtPMDVXMmdQZzRrVWhHZXFPNklZMDlFUE9jVHVwdzc3UFJIb1dPZzR4TmNxRVFOMnYyQzFscjA5WTkgam9obnlpbgo=\"}}"
    # 关闭文件
    fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} "{\"execute\":\"guest-file-close\", \"arguments\":{\"handle\":${handle}}}"
}

agent_passwd() {
    local usr_srv_port=$1;shift 1
    local domain=$1;shift 1
    local username=$1;shift 1
    local password=$(echo -en "${1}" | base64);shift 1
    for it in ${*}; do
        args="${args},\"$it\""
    done
    debug_msg "'{\"execute\":\"guest-set-user-password\",\"arguments\":{\"username\":\"${username}\",\"password\":\"${password}\",\"crypted\":false}}'"
    fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} "'{\"execute\":\"guest-set-user-password\",\"arguments\":{\"username\":\"${username}\",\"password\":\"${password}\",\"crypted\":false}}'"
}
#agent_command root@10.32.147.3:60022 p3sywin161 cmd.exe /c dir
agent_command() {
    local usr_srv_port=$1;shift 1
    local domain=$1;shift 1
    local cmd=$1;shift 1
    local args="\"${1:-}\"";shift 1 || true
    for it in ${*}; do
        args="${args},\"$it\""
    done
    debug_msg "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"${cmd}\",\"arg\":[${args}],\"capture-output\":true}}"
    local out=$(fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} "'{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"${cmd}\",\"arg\":[${args}],\"capture-output\":true}}'" | jq ".return.pid")
    out=$(fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} "'{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":${out}}}'")
    local exitcode=$(printf "%s" $out | jq -c ".return.exitcode")
    local exited=$(printf "%s" $out | jq -c ".return.exited")
    printf "%s" $out | jq -cr '.return."out-data"' | base64 -d
    return $exitcode
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} -q -l <int> -d -h passwd/exec <args>
        exec <usr_srv_port> <domain> <cmd> <arg>
        passwd <usr_srv_port> <domain> <username> <password>
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
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
    case "${1:-}" in
        passwd)
            shift
            echo 'virsh set-user-password --domain <uuid> --user root --password password'
            agent_passwd ${*}
            ;;
        exec)
            shift
            agent_command ${*}
            ;;
        *)
            usage "passwd/exec"
            ;;
    esac
}
main "$@"
