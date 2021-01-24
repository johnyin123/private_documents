#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("netlab-wireguard.sh - 3b8d952 - 2021-01-24T11:57:01+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
gen_network() {
cat <<EOF >lab-wiregurad.conf
#[name]="type" type:R/S/N (router,switch,node)
MAP_NODES=(
    [R1]=R
    [R2]=R
    [R3]=R
    [SW1]=S
    [SW2]=S
    [SW3]=S
    [h1]=N
    [j1]=N
    [h2]=N
    [j2]=N
    [h3]=N
    [j3]=N
    )
#[node:ip/prefix]=node:ip/prefix
MAP_LINES=(
    [R1:172.16.16.1/30]=R2:172.16.16.2/30
    [R1:172.16.16.5/30]=R3:172.16.16.6/30
    [R2:172.16.16.9/30]=R3:172.16.16.10/30
    [R1:10.0.1.1/24]=SW1:
    [R2:10.0.2.1/24]=SW2:
    [R3:10.0.3.1/24]=SW3:
    [h1:10.0.1.100/24]=SW1:
    [j1:10.0.1.101/24]=SW1:
    [h2:10.0.2.100/24]=SW2:
    [j2:10.0.2.101/24]=SW2:
    [h3:10.0.3.100/24]=SW3:
    [j3:10.0.3.101/24]=SW3:
    )
#routes delm ,
NODES_ROUTES=(
    [h1]="default via 10.0.1.1"
    [j1]="default via 10.0.1.1"
    [h2]="default via 10.0.2.1"
    [j2]="default via 10.0.2.1"
    [h3]="default via 10.0.3.1"
    [j3]="default via 10.0.3.1"
    )
EOF
    ${DIRNAME}/netlab.sh -s lab-wiregurad.conf
}
gen_wg() {
    local prikey_R1=$(try wg genkey)
    local pubkey_R1="$(echo -n ${prikey_R1} | try wg pubkey)"
    local prikey_R2=$(try wg genkey)
    local pubkey_R2="$(echo -n ${prikey_R2} | try wg pubkey)"
    local prikey_R3=$(try wg genkey)
    local pubkey_R3="$(echo -n ${prikey_R3} | try wg pubkey)"
    # [R1:172.16.16.1/30]=R2:172.16.16.2/30
    # [R1:172.16.16.5/30]=R3:172.16.16.6/30
    # [R2:172.16.16.9/30]=R3:172.16.16.10/30
    # [R1:10.0.1.1/24]=SW1:
    # [R2:10.0.2.1/24]=SW2:
    # [R3:10.0.3.1/24]=SW3:
    ${DIRNAME}/wireguard2.sh --pkey "${prikey_R1}" --addr 172.16.1.1/24 --pubport 9901        >wg_R1.conf
    ${DIRNAME}/wireguard2.sh --onlypeer --pubkey "${pubkey_R2}" --endpoint 172.16.16.2:9901 --allows "10.0.2.0/24" >>wg_R1.conf
    ${DIRNAME}/wireguard2.sh --onlypeer --pubkey "${pubkey_R3}" --endpoint 172.16.16.6:9901 --allows "10.0.3.0/24" >>wg_R1.conf
    ${DIRNAME}/wireguard2.sh --pkey "${prikey_R2}" --addr 172.16.1.2/24 --pubport 9901        >wg_R2.conf
    ${DIRNAME}/wireguard2.sh --onlypeer --pubkey "${pubkey_R1}" --endpoint 172.16.16.1:9901 --allows "10.0.1.0/24"  >>wg_R2.conf
    ${DIRNAME}/wireguard2.sh --onlypeer --pubkey "${pubkey_R3}" --endpoint 172.16.16.10:9901 --allows "10.0.3.0/24" >>wg_R2.conf
    ${DIRNAME}/wireguard2.sh --pkey "${prikey_R3}" --addr 172.16.1.3/24 --pubport 9901                   >wg_R3.conf
    ${DIRNAME}/wireguard2.sh --onlypeer --pubkey "${pubkey_R1}" --endpoint 172.16.16.5:9901 --allows "10.0.1.0/24"  >>wg_R3.conf
    ${DIRNAME}/wireguard2.sh --onlypeer --pubkey "${pubkey_R2}" --endpoint 172.16.16.9:9901 --allows "10.0.2.0/24"  >>wg_R3.conf
}

tmux_new() {
    local sess="$1"
    maybe_dryrun tmux new-session -d -s "${sess}";
    maybe_dryrun tmux set-option -g mouse on
    maybe_dryrun tmux set-window-option -g mode-keys vi
}

tmux_attach() {
    local sess="$1"
    if tmux has-session -t "${sess}" 2> /dev/null; then
        [ -n "${TMUX:-}" ] && exit_msg "Already in tmux env!!\n"
        maybe_dryrun tmux attach-session -t "${sess}"
        exit 0
    fi
}

tmux_window() {
    local sess="$1"
    local window="$2"
    local pane="$3"
    local cmd="${4-}"
    maybe_dryrun tmux new-window -t "${sess}" -n "${window}"
    maybe_dryrun tmux select-pane -T "${pane}"
    [ -z "${cmd}" ] || maybe_dryrun tmux send-keys -t "${sess}:${window}" "'${cmd}'" Enter
}

tmux_netns_shell() {
    local sess="$1"
    local window="$2"
    local info="$3"
    local ns_name="${4:-}" 
    maybe_dryrun tmux send-keys -t "${sess}:${window}" "'exec env -i \
        SHELL=/bin/bash \
        HOME=/root \
        TERM=${TERM} \
        PS1="[${info}${ns_name:+@${ns_name}}]\$PS1" \
        ${ns_name:+ip netns exec ${ns_name}} \
        /bin/bash --noprofile --norc'" Enter
}

main() {
    local sess="wglab"
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
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
    file_exists ${DIRNAME}/wireguard2.sh || exit_msg "need ${DIRNAME}/wireguard2.sh\n"
    file_exists ${DIRNAME}/netlab.sh || exit_msg "need ${DIRNAME}/netlab.sh\n"
    tmux_attach "$sess"
    gen_wg
    gen_network
    maybe_netns_run "ping -c2 10.0.2.100" "h1"
    maybe_netns_run "ping -c2 10.0.3.100" "h1"

    maybe_netns_run "wg-quick up ${DIRNAME}/wg_R1.conf" "R1"
    maybe_netns_run "wg-quick up ${DIRNAME}/wg_R2.conf" "R2"
    maybe_netns_run "wg-quick up ${DIRNAME}/wg_R3.conf" "R3"

    maybe_netns_run "ping -c2 10.0.2.100" "h1"
    maybe_netns_run "ping -c2 10.0.3.100" "h1"

    tmux_new "${sess}"
    tmux_window "${sess}" "R1" "shell"
    tmux_netns_shell "${sess}" "R1" "shell" "R1"
    tmux_window "${sess}" "R2" "shell"
    tmux_netns_shell "${sess}" "R2" "shell" "R2"
    tmux_window "${sess}" "R3" "shell"
    tmux_netns_shell "${sess}" "R3" "shell" "R3"
    tmux_window "${sess}" "h1" "shell"
    tmux_netns_shell "${sess}" "h1" "shell" "h1"
    return 0
}
main "$@"
