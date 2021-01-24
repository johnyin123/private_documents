#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("tmux_test.sh - 3937623 - 2021-01-23T17:12:30+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
tmux_hsplit() {
    local sess="$1"
    local window="$2"
    local cmd="'$3'"
    maybe_dryrun tmux split-window -t "${sess}:${window}" -h
    maybe_dryrun tmux send-keys -t "${sess}:${window}" "${cmd}" Enter
}

tmux_vsplit() {
    local sess="$1"
    local window="$2"
    local cmd="'$3'"
    maybe_dryrun tmux split-window -t "${sess}:${window}" -v
    maybe_dryrun tmux send-keys -t "${sess}:${window}" "${cmd}" Enter
}

tmux_new() {
    local sess="$1"
    local window="$2"
    local cmd="'$3'"
    maybe_dryrun tmux new-session -d -s "${sess}";
    maybe_dryrun tmux set-option -t "${sess}" mouse on
    maybe_dryrun tmux set-window-option -t "${sess}" mode-keys vi
    maybe_dryrun tmux new-window -t "${sess}" -n "${window}"
    maybe_dryrun tmux send-keys -t "${sess}:${window}" "${cmd}" Enter
}

tmux_shell() {
    local sess="$1"
    if tmux has-session -t "${sess}" 2> /dev/null; then
        [ -n "${TMUX:-}" ] && exit_msg "Already in tmux env!!\n"
        maybe_dryrun tmux attach-session -t "${sess}"
        exit 0
    fi
}

main() {
    local sess="mylab"
    local ns_name="testns"
    tmux_shell "${sess}"
    setup_ns "${ns_name}" || { error_msg "node ${ns_name} init netns error\n"; return 1; }
    tmux_new "${sess}" "G1" "exec ip netns exec ${ns_name} /bin/bash --noprofile --rcfile <(echo \"PS1='${ns_name} $ '\")"
    tmux_hsplit "${sess}" "G1" "exec ip netns exec ${ns_name} /bin/bash --noprofile --rcfile <(echo \"PS1='${ns_name} $ '\")"
    tmux_vsplit "${sess}" "G1" "exec ip netns exec ${ns_name} /bin/bash --noprofile --rcfile <(echo \"PS1='${ns_name} $ '\")"
    #tmux kill-window -t "${sess}":$(tmux list-windows -t "${sess}" -F "1" | head -n 1)
    echo "FFF"
    return 0
}
main "$@"
