#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("tmux_test.sh - 3b8d952 - 2021-01-24T11:57:01+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
tmux_hsplit() {
    local sess="$1"
    local window="$2"
    local pane="$3"
    local cmd="${4-}"
    maybe_dryrun tmux split-window -t "${sess}:${window}" -h
    maybe_dryrun tmux select-pane -T "${pane}"
    [ -z "${cmd}" ] || maybe_dryrun tmux send-keys -t "${sess}:${window}" "'${cmd}'" Enter
}

tmux_vsplit() {
    local sess="$1"
    local window="$2"
    local pane="$3"
    local cmd="${4-}"
    maybe_dryrun tmux split-window -t "${sess}:${window}" -v
    maybe_dryrun tmux select-pane -T "${pane}"
    [ -z "${cmd}" ] || maybe_dryrun tmux send-keys -t "${sess}:${window}" "'${cmd}'" Enter
}

tmux_new() {
    local sess="$1"
    local window="$2"
    local pane="$3"
    local cmd="${4-}"
    maybe_dryrun tmux new-session -d -s "${sess}";
    maybe_dryrun tmux set-option -g mouse on
    maybe_dryrun tmux set-window-option -g mode-keys vi
    maybe_dryrun tmux new-window -t "${sess}" -n "${window}"
    maybe_dryrun tmux select-pane -T "${pane}"
    [ -z "${cmd}" ] || maybe_dryrun tmux send-keys -t "${sess}:${window}" "'${cmd}'" Enter
}

tmux_attach() {
    local sess="$1"
    if tmux has-session -t "${sess}" 2> /dev/null; then
        [ -n "${TMUX:-}" ] && exit_msg "Already in tmux env!!\n"
        maybe_dryrun tmux attach-session -t "${sess}"
        exit 0
    fi
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
    local sess="mylab"
    local window="myshell"
    local ns_name="testns"
    tmux_attach "${sess}"
    netns_exists "${ns_name}" && cleanup_ns "${ns_name}"
    setup_ns "${ns_name}" || { error_msg "node ${ns_name} init netns error\n"; return 1; }
    tmux_new "${sess}" "${window}" "G1"
    tmux_netns_shell "${sess}" "${window}" "G1" 
    tmux_hsplit "${sess}" "${window}" "G2"
    tmux_netns_shell "${sess}" "${window}" "G2" "${ns_name}"
    tmux_vsplit "${sess}" "${window}" "G3"
    tmux_netns_shell "${sess}" "${window}" "G3" "${ns_name}"
    #tmux kill-window -t "${sess}":$(tmux list-windows -t "${sess}" -F "1" | head -n 1)
    echo "FFF"
    return 0
}
main "$@"
