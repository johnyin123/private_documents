#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
TAPDEV_NUM=9

mk_support() {
    local ssh_connection=${1}
    local ssh_port=${2}
    try ssh -tt -p${ssh_port} ${ssh_connection} "(grep -v PermitTunnel /etc/sshd/sshd_config ;echo PermitTunnel yes) | tee /etc/sshd/sshd_config" || true
    return 0
}

ssh_tunnel() {
    local local_br=${1}
    local remote_br=${2}
    local ssh_connection=${3}
    local ssh_port=${4}
    #exec 5> >(ssh -tt -o StrictHostKeyChecking=no -p${port} ${user}@${host} > /dev/null 2>&1)
    ssh \
        -o PermitLocalCommand=yes \
        -o LocalCommand="ip link set dev tap${TAPDEV_NUM} up;ip link set dev tap${TAPDEV_NUM} master ${local_br}" \
        -o Tunnel=ethernet -w ${TAPDEV_NUM}:${TAPDEV_NUM} \
        -p${ssh_port} ${ssh_connection} "ip link set dev tap${TAPDEV_NUM} up;ip link set dev tap${TAPDEV_NUM} master ${remote_br}" &
    echo "$!"
}

main() {
    local local_br=${1:-br-ext}
    local remote_br=${2:-br-data.149}
    local ssh_connection=${3:-root@10.32.147.16}
    local ssh_port=${4:-60022}
    is_user_root || exit_msg "root need!!\n"
    pid="$(ssh_tunnel ${local_br} ${remote_br} ${ssh_connection} ${ssh_port})"
    /bin/bash --rcfile <(echo "PS1=\"ssh_tunnel:${ssh_connection}> \"") || true
    try "kill -9 ${pid:-} &> /dev/null"
    info_msg "Exit!!\n"
    return 0
}
main "$@"
