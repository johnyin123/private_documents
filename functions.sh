#!/bin/echo Warnning, this library must only be sourced!
# shellcheck disable=SC2086 disable=SC2155

# TO BE SOURCED ONLY ONCE:
if [ -z ${__functions_inc+x} ]; then
    __functions_inc=1
else
    return 0
fi
# Disable unicode.
LC_ALL=C
LANG=C

#set -o pipefail  # trace ERR through pipes,only available on Bash
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

VERSION+=("functions.sh - 9882be5 - 2021-08-11T13:58:12+08:00")
#shopt -s expand_aliases
#alias

dummy() { :; }

list_func() {
    #function_name startwith _ is private usage!
    typeset -f | awk '/ \(\) $/ && !/^main / {print $1}' | grep -v "^_"
    alias
#    local fncs=$(declare -F -p | cut -d " " -f 3 | grep -v "^_")
#    echo $fncs
}

uuid() {
    cat /proc/sys/kernel/random/uuid
}

# save file data(base64) from __BIN_BEGINS__ to out.
# out is null then output to stdout
# echo "__BIN_BEGINS__" >> test.sh && base64 data.bin >> test.sh
# save_bin ${DIRNAME}/${SCRIPTNAME} | tar -zpvx -C $WORK_DIR
save_bin() {
    local file=$1
    local out=${2:-}
    defined DRYRUN && {
        info_msg "${file} bin-data to ${out:-stdout}\n"
        return 0
    }
    local bin_start=$(awk '/^__BIN_BEGINS__/ { print NR + 1; exit 0; }' ${file})
    # vim -e -s -c 'g/start_pattern/+1,/stop_pattern/-1 p' -cq file.txt
    # awk '/start_pattern/,/stop_pattern/' file.txt
    # sed -n /start_pattern/,/stop_pattern/p file.txt
    tail -n +${bin_start} ${file} | eval "base64 -d ${out:+> ${out}}"
}

#fetch http://a.com/abc.zip aaa.zip
fetch() {
    if type wget > /dev/null 2>&1 ; then
        try wget --no-check-certificate -O "${2}" "${1}" >/dev/null 2>&1
    elif type curl > /dev/null 2>&1 ; then
        try curl --insecure --remote-name -o "${2}" "${1}" >/dev/null 2>&1
    else
        exit_msg 'Warning: Neither wget nor curl is available. online updates unavailable'
    fi
}

# divide %1/%2 rounding up
ceil() {
    divide=$1
    by=$2
    echo $(((divide+by-1)/by))
}

is_in_list_separator_helper ()
{
    local sep element list
    sep=${1}
    shift
    element=${1}
    shift
    list=${*}
    echo ${list} | grep -qe "^\(.*${sep}\)\?${element}\(${sep}.*\)\?$"
}

is_in_space_sep_list ()
{
    local element
    element=${1}
    shift
    is_in_list_separator_helper "[[:space:]]" "${element}" "${*}"
}

is_in_comma_sep_list ()
{
    local element
    element=${1}
    shift
    is_in_list_separator_helper "," "${element}" "${*}"
}


# Usage:
#   join , a "b c" d #a,b c,d
#   join / var local tmp #var/local/tmp
#   join , "${FOO[@]}" #a,b,c
# ----------------------------------------------
join() { local IFS="${1}"; shift; echo "${*}"; }

human_readable_disk_size() {
    local bytes=$1
    local __M=$((1048576))
    local __G=$((1024*__M))
    local __T=$((1024*__G))
    local __P=$((1024*__T))
    if [ $bytes -ge $__P ]; then safe_echo $((bytes/__P))P; return; fi
    if [ $bytes -ge $__T ]; then safe_echo $((bytes/__T))T; return; fi
    if [ $bytes -ge $__G ]; then safe_echo $((bytes/__G))G; return; fi
    safe_echo $((bytes/__M))M
}

#SIZE=$(($(echo $SIZE | sed 's|[bB]||' | sed 's|[kK]|* 1024|' | sed 's|[mM]|* 1024 * 1024|' | sed 's|[gG]|* 1024 * 1024 * 1024|')))
human_readable_format_size()
{
    local size=$1
    local fs=
    if [[ $size -ge 1073741824 ]]; then
        fs=$(echo - | awk "{print $size/1073741824}")
        #fs=${fs/./,}
        printf "%.2f GiB" $fs
    else
        if [[ $size -ge 1048576 ]]; then
            fs=$(echo - | awk "{print $size/1048576}")
            #fs=${fs/./,}
            printf "%.2f MiB" $fs
        else
            if [[ $size -ge 1024 ]]; then
                fs=$(echo - | awk "{print $size/1024}")
                #fs=${fs/./,}
                printf "%.2f KiB" $fs
            else
                printf "%d Bytes" $size
            fi
        fi
    fi
}

setup_ns() {
    local ns_name="$1"
    try $(truecmd ip) netns add ${ns_name}
    maybe_netns_run "ip addr add 127.0.0.1/8 dev lo" "${ns_name}"
    maybe_netns_run "ip link set lo up" "${ns_name}"
    try mkdir -p "/etc/netns/$ns_name"
}

maybe_netns_addlink() {
    local link="$1"
    local ns_name="${2:-}"
    local newname="${3:-}"
    try $(truecmd ip) link set "${link}" ${ns_name:+netns ${ns_name} }${newname:+name ${newname} }up
}

# cat <<EOF >${ovlerlay}/a.sh
# #!/usr/bin/env bash
# mount -t proc proc /proc
# mount -t sysfs /sys sys
# hostname mydocer
# /etc/init.d/ssh start
# export PS1="mydocker##\033[1;31m\u\033[m@\033[1;32m\h:\033[33;1m\w\033[m$"
# exec /bin/bash --noprofile --norc -o vi
# EOF
# chmod 755 /a.sh
# docker_shell "mydocker" "${ns_name}" "$rootfs" "/a.sh" "args"
docker_shell() {
    local info="$1"
    local ns_name="${2}"
    local rootfs="${3}"; shift 3
    local shell="${1:-/bin/bash --noprofile --norc -o vi}"; shift || true
    local args="${@:-}"
    local ps1=[${info}${rootfs:+:${rootfs}}${ns_name:+@${ns_name}}]
    local colors=$($(truecmd tput) colors 2> /dev/null)
    if [ $? = 0 ] && [ ${colors} -gt 2 ]; then
        ps1+="\033[1;31m\u\033[m@\033[1;32m\h:\033[33;1m\w\033[m$"
    else
        ps1+="\u@\h:\w$"
    fi

    defined DRYRUN && { blue>&2 "DRYRUN: ";purple>&2 "docker: ${ns_name}${rootfs:+@rootfs:${rootfs}} ${shell} ${args}\n"; return 0; }
    ip netns exec "${ns_name}" \
        unshare --mount --ipc --uts --pid --fork --mount-proc -- \
            ${rootfs:+$(truecmd chroot) ${rootfs}} \
            /usr/bin/env -i \
            SHELL=/bin/bash \
            HOME=${HOME:-/} \
            TERM=${TERM} \
            HISTFILE= \
            COLORTERM=${COLORTERM} \
            PS1=${ps1} \
            ${shell} ${args} || true
}

# tmux select-window -t <session-name>:<windowID>
# tmux send-keys -t "${sess}:${window}" "history -c;reset" Enter
tmux_input() {
    local sess="$1" window="$2" input="$3"
    defined DRYRUN && { blue>&2 "DRYRUN: ";purple>&2 "tmux send-keys -t ${sess}:${window} \"${input}\" Enter\n"; return 0; }
    tmux send-keys -t "${sess}:${window}" "${input}" Enter
    # tmux capture-pane -t "${sess}:${window}" -p
}

maybe_tmux_netns_chroot() {
    local sess="$1" window="$2"
    local ns_name="${3:-}" rootfs="${4:-}"
    local unshared="${5:-}"
    defined DRYRUN && { blue>&2 "DRYRUN: ";purple>&2 "tmux ${sess}:${window}${rootfs:+rootfs=${rootfs}}${ns_name:+@${ns_name}}\n"; return 0; }
    tmux has-session -t "${sess}" 2> /dev/null && tmux new-window -t "${sess}" -n "${window}" || tmux set-option -g status off\; new-session -d -n "${window}" -s "${sess}"
    local ps1=[${window}${rootfs:+:${rootfs}}${ns_name:+@${ns_name}}]
    local colors=$($(truecmd tput) colors 2> /dev/null)
    if [ $? = 0 ] && [ ${colors} -gt 2 ]; then
        ps1+="\033[1;31m\u\033[m@\033[1;32m\h:\033[33;1m\w\033[m$"
    else
        ps1+="\u@\h:\w$"
    fi

    defined DRYRUN && { blue>&2 "DRYRUN: ";purple>&2 "tmux: ${sess}:${window}{rootfs:+@rootfs:${rootfs}} shell\n"; return 0; }
    tmux send-keys -t "${sess}:${window}" "exec \
        ${ns_name:+$(truecmd ip) netns exec ${ns_name}} \
        ${unshared:+$(truecmd unshare) --mount --ipc --uts --pid --fork --mount-proc --} \
        ${rootfs:+$(truecmd chroot) ${rootfs}} \
        /bin/env -i \
        SHELL=/bin/bash \
        HOME=${HOME:-/} \
        TERM=\${TERM} \
        HISTFILE= \
        COLORTERM=\${COLORTERM} \
        PS1='${ps1}' \
        /bin/bash --noprofile --norc -o vi" Enter
    tmux send-keys -t "${sess}:${window}" "history -c;reset" Enter
    # tmux send-keys -t "${sess}:${window}" "stty cols 1000" Enter
}
# maybe_netns_shell "busybox" "${ns_name}" "rootfs" "busybox" "sh -l"
# maybe_netns_shell "busybox" "${ns_name}" "rootfs" "/bin/sh" "-l"
maybe_netns_shell() {
    local info="$1"; shift || true
    local ns_name="${1:-}"; shift || true
    local rootfs="${1:-}"; shift || true
    local shell="${1:-/bin/bash}"; shift || true
    local args="${@:---noprofile --norc -o vi}"
    local ps1=[${info}${rootfs:+:${rootfs}}${ns_name:+@${ns_name}}]
    local colors=$($(truecmd tput) colors 2> /dev/null)
    if [ $? = 0 ] && [ ${colors} -gt 2 ]; then
        ps1+="\033[1;31m\u\033[m@\033[1;32m\h:\033[33;1m\w\033[m$"
    else
        ps1+="\u@\h:\w$"
    fi

    local cmds="${ns_name:+$(truecmd ip) netns exec ${ns_name}} \
        ${rootfs:+$(truecmd chroot) ${rootfs}} \
        /bin/env -i \
        SHELL=${shell} \
        HOME=${HOME:-/} \
        TERM=${TERM} \
        HISTFILE= \
        COLORTERM=${COLORTERM} \
        PS1=${ps1} \
        ${shell} ${args}"
    defined DRYRUN && { blue>&2 "DRYRUN: ";purple>&2 "$cmds\n"; stdin_is_terminal || cat >&2; return 0; }
    trap "echo 'CTRL+C!!!!'" SIGINT
    ${cmds} || true
    trap - SIGINT
}

#     cmds="
#         touch log
#         ls -l /
#     "
#     maybe_netns_run "" "${ns_name}" "" <<< $cmds
#     echo "$cmds" | maybe_netns_run
#     cat <<EOF | maybe_netns_run "" "${ns_name}" ""
#         echo hello > log
#         ip a
# EOF
#     echo -n "msg" | maybe_netns_run cat "${ns_name}" ""
#     maybe_netns_run "bash -s" "${ns_name}" "" <<EOF
#         ifconfig
#         start-stop-daemon --start --quiet --background --exec '/sbin/zebra'
# EOF
maybe_netns_run() {
    local cmds="${1:-$(cat)}"
    local ns_name="${2:-}"
    local rootfs="${3:-}"
    try "${ns_name:+$(truecmd ip) netns exec ${ns_name} }${rootfs:+$(truecmd chroot) ${rootfs} }${cmds}"
}

netns_exists() {
    local ns_name="$1"
    # Check if a namespace named $ns_name exists.
    # Note: Namespaces with a veth pair are listed with '(id: 0)' (or something). We need to remove this before lookin
    # /var/run/netns/${ns_name} ?? exists
    ip netns list | sed 's/ *(id: [0-9]\+)$//' | grep --quiet --fixed-string --line-regexp "${ns_name}"
}

cleanup_ns() {
    local ns_name="$1"
    try $(truecmd ip) netns del ${ns_name} || true
    try rm -rf "/etc/netns/$ns_name" || true
}

bridge_exists() {
    local bridge="$1"
    local ns_name="${2:-}"
    ${ns_name:+$(truecmd ip) netns exec "${ns_name}" }[ -e /sys/class/net/${bridge}/bridge/bridge_id ]
}

maybe_netns_bridge_addlink() {
    local bridge="$1"
    local link="$2"
    local ns_name="${3:-}"
    maybe_netns_run "ip link set ${link} master ${bridge}" "${ns_name}"
    maybe_netns_run "ip link set dev ${link} up" "${ns_name}"
}

maybe_netns_bridge_dellink() {
    local link="$1"
    local ns_name="${2:-}"
    maybe_netns_run "ip link set ${link} promisc off" "${ns_name}" || true
    maybe_netns_run "ip link set ${link} down" "${ns_name}" || true
    maybe_netns_run "ip link set dev ${link} nomaster" "${ns_name}" || true
}

maybe_netns_setup_bridge() {
    local bridge="$1"
    local ns_name="${2:-}"
    maybe_netns_run "ip link add ${bridge} type bridge" "${ns_name}"
    maybe_netns_run "ip link set ${bridge} up" "${ns_name}"
}

maybe_netns_setup_veth() {
    local veth_left="$1"
    local veth_right="$2"
    local ns_name="${3:-}"
    maybe_netns_run "ip link add ${veth_left} type veth peer name ${veth_right}" "${ns_name}"
}

cleanup_link() {
    local link="$1"
    local ns_name="${2:-}"
    maybe_netns_run "ip link delete ${link}" "${ns_name}" || true
}

# /bin/mount -t proc proc /proc
# /bin/mount -t sysfs /sys sys
# /bin/mount -t devtmpfs none /dev
# [ -e /dev/console ] || /bin/mknod -m 622 /dev/console c 5 1
# [ -e /dev/null ]    || /bin/mknod -m 666 /dev/null c 1 3
# [ -e /dev/zero ]    || /bin/mknod -m 666 /dev/zero c 1 5
# [ -e /dev/ptmx ]    || /bin/mknod -m 666 /dev/ptmx c 5 2
# [ -e /dev/tty ]     || /bin/mknod -m 666 /dev/tty c 5 0
# [ -e /dev/random ]  || /bin/mknod -m 444 /dev/random c 1 8
# [ -e /dev/urandom ] || /bin/mknod -m 444 /dev/urandom c 1 9
# [ -d /dev/pts ]     || /bin/mkdir -p /dev/pts
# /bin/mount -t devpts -o gid=4,mode=620 none /dev/pts
# echo "start shm"
# [ -d /dev/shm ]     || /bin/mkdir -p /dev/shm
# /bin/mount -t tmpfs none /dev/shm/
# echo "start dbus"
# /bin/dbus-uuidgen > /var/lib/dbus/machine-id
# [ -d /var/run/dbus ]|| /bin/mkdir -p /var/run/dbus
# /bin/dbus-daemon --config-file=/usr/share/dbus-1/system.conf --print-address
#
#start process with special PID: echo 1 > /proc/sys/kernel/ns_last_pid;  .....
setup_overlayfs() {
    local lower="$1"
    local rootmnt="$2"
    local overlay_size_mb="${3:-1}"
    try mkdir -p ${rootmnt}/tmpfs
    try mount -t tmpfs tmpfs -o size=${overlay_size_mb}M ${rootmnt}/tmpfs
    try mkdir -p ${rootmnt}/tmpfs/upper ${rootmnt}/tmpfs/work
    try mount -t overlay overlay -o lowerdir=${lower},upperdir=${rootmnt}/tmpfs/upper,workdir=${rootmnt}/tmpfs/work ${rootmnt}/
}

cleanup_overlayfs() {
    local rootmnt="$1"
    local keep_tmpfs="${2:-}"
    try umount ${rootmnt} || true
    try "${keep_tmpfs:+echo need manul exec: }umount ${rootmnt}/tmpfs" || true
    try "${keep_tmpfs:+echo need manul exec: }rm -rf ${rootmnt}/tmpfs" || true
}

get_ipaddr() {
    $(truecmd ip) -4 -br addr show ${1} | $(truecmd grep) -Po "\\d+\\.\\d+\\.\\d+\\.\\d+"
}

#confirm default N,when timeout
confirm() {
    local msg=${1:-confirm}
    local tmout=${2:-}
    read ${tmout:+-t ${tmout}} -p "${msg} [y/N] " -n 1
    if [ "${REPLY}" = "Y" ] || [ "${REPLY}" = "y" ]; then
        return 0
    fi
    return 1
}

##Usage: check_http_status 'http://www.example.com'
check_http_status() {
    local url=$1
    local status=$(curl -s -o /dev/null -w '%{http_code}' $url)
    safe_echo $status
}

stdin_is_terminal() {
    [ -t 0 ]
}

stdout_is_terminal() {
    [ -t 1 ]
}

stderr_is_terminal() {
    [ -t 2 ]
}

is_user_root() {
    [ "$(id -u)" -eq 0 ]
}

# auto_su() {
#   ARGS=( "$@" )
#   [[ $UID == 0 ]] || exec sudo -p "$SCRIPTNAME  must be run as root. Please enter the password for %u to continue: " -- "$BASH" -- "$DIRNAME/$SCRIPTNAME" "${ARGS[@]}"
# }

min() { [ "$1" -le "$2" ] && echo "$1" || echo "$2"; }
max() { [ "$1" -ge "$2" ] && echo "$1" || echo "$2"; }
#cursor op
erase_line() {
    printf '%b' $'\e[1K\r'
}
cursor_onoff() {
    local op="$1"
    case "${op}" in
        hide) printf "\e[?25l" ;;
        show) printf "\e[?25h" ;;
        *) return 1 ;;
    esac
    return 0
}
cursor_moveto() {
    local x="${1}"
    local y="${2}"
    ## write
    printf "\e[%d;%d;f" ${y} ${x}
    return 0
}
cursor_pos() {
    local CURPOS
    read -sdR -p $'\E[6n' CURPOS
    CURPOS=${CURPOS#*[} # Strip decoration characters <ESC>[
    echo "${CURPOS}"    # Return position in "row;col" format
}
cursor_row() {
    local COL
    local ROW
    IFS=';' read -sdR -p $'\E[6n' ROW COL
    echo "${ROW#*[}"
}
cursor_col() {
    local COL
    local ROW
    IFS=';' read -sdR -p $'\E[6n' ROW COL
    echo "${COL}"
}
safe_echo() {
    printf -- '%b\n' "$*"
}

cprintf() {
    local color=$1
    local fmt=$2
    shift 2
    local  EC=$'\033'    # escape char
    local  EE=$'\033[0m' # escape end
    # if stdout is console, turn on color output.
    stdout_is_terminal && printf "${EC}[1;${color}m${fmt}${EE}" "$@" || printf "${fmt}" "$@"
}

# echo "hello {{DISK_DEV}} \$(({{VAL}}*2))" | render_tpl2 vm
# same as render_tpl  #LHS='${' RHS='}'
# REPS default two LHS/RHS like {{ }}
# LHS='%' RHS='%'
render_tpl2() {
    local str="$(cat)"
    local arr=$1
    local SEQN="$(seq 1 ${REPS:-2})"
    for arg in $(array_print_label ${arr}) ; do
        local sub="${LHS:=$(printf '{%.0s' $SEQN)}${arg}${RHS:=$(printf '}%.0s' $SEQN)}"
        local val="$(array_get ${arr} "$arg")"
        str="${str//"$sub"/$val}"
    done
    cat <<< "$str"
}
#
# declare -A vm=([DISK_DEV]=vdc [VAL]=2)
# echo "hello '\${DISK_DEV}' \$((\${VAL}*2))" | render_tpl vm
render_tpl() {
    local arr=$1
    local j= LHS= RHS= line=
    for j in $(array_print_label ${arr}) ; do eval "local $j=\"$(array_get ${arr} $j)\""; done
    while IFS= read -r line ; do
        while [[ "$line" =~ (\$\{[a-zA-Z_][a-zA-Z_0-9]*\}) ]] ; do
            LHS=${BASH_REMATCH[1]}
            RHS="$(eval echo "\"$LHS\"")"
            line=${line//$LHS/$RHS}
        done
        printf "%s\n" "$line"
        # eval "echo \"$line\"" #risk
    done
    return 0
}

# declare -A abc;
# read_kv abc <<< $(cat kv.txt)
# array_print_label abc
# array_print abc
print_kv() {
    local j=
    for j in $(array_print_label $1) ; do safe_echo "$j=$(array_get $1 $j)"; done
}

empty_kv() {
    local j=
    for j in $(array_print_label $1) ; do unset "$1[$j]"; done
}

read_kv() {
    local line=
    while IFS= read -r line; do
        [[ ${line} =~ ^\ *#.*$ ]] && continue #skip comment line
        [[ ${line} =~ ^\ *$ ]] && continue #skip blank
        eval "$1[${line%%=*}]=${line#*=}"
    done
}

# choices=("1xx" "choine 1" "2" "choice 2")
# id=$(dialog "title xxa" "menu xxx" choices[@])
# echo $id
dialog() {
    local title="${1}"
    local menu="${2}"
    declare -a items=("${!3}")
    local item=$(eval $(resize) && whiptail --notags \
        --title "${title}" \
        --menu "${menu}" \
        $LINES $COLUMNS $(( $LINES - 12 )) \
        "${items[@]}" 3>&1 1>&2 2>&3 || true)
    safe_echo "${item}"
}
##################################################
# Assign variable one scope above the caller
# Usage: local "$1" && upvar $1 "value(s)"
# Param: $1  Variable name to assign value to
# Param: $*  Value(s) to assign.  If multiple values, an array is
#            assigned, otherwise a single value is assigned.
# Example:
#    f() { local b; g b; echo $b; }
#    g() { local "$1" && upvar $1 bar; }
#    f  # Ok: b=bar
upvar() {
    if unset -v "$1"; then           # Unset & validate varname
        if (( $# == 2 )); then
            eval $1=\"\$2\"          # Return single value
        else
            eval $1=\(\"\${@:2}\"\)  # Return array
        fi
    fi
}

# item=(ERR SUM)
# safe_read_cfg demo.cfg item
# echo "OK =${OK:-oo},ERR=$ERR"
safe_read_cfg()
{
    local cfg="${1}"
    local allow_array="${2}"
    [ -f "$cfg" ] || return 1
    local i=0
    local len=$(array_size "${allow_array}")
    local pattern=$(array_get $allow_array 0)
    for (( i=1; i<len; ++i )); do
        pattern="$pattern|$(array_get $allow_array $i)"
    done
    source <(grep -E "^\s*($pattern)=" $cfg)
}

getinientry() {
    local CONF=$1
    grep "^\[" "${CONF}" | sed "s/\[//;s/\]//"
}

readini() {
    local ENTRY=$1
    local CONF=$2
    local INFO=$(grep -v ^$ "${CONF}"\
        | sed -n "/\[${ENTRY}\]/,/^\[/p" \
        | grep -v ^'\[') && eval "${INFO}"
}
##################################################
# Log level constants
LOG_ERROR=0       # Level error
LOG_WARNING=1     # Level warning
LOG_INFO=2        # Level info
LOG_DEBUG=3       # Level debug

# Log level names
LOG_LEVELNAMES=('ERROR' 'WARN ' 'INFO ' 'DEBUG')

# Global constants definition end }}

# Show log whose level less than this
log_level=2
# Default date fmt
date_fmt='%Y-%m-%d %H:%M:%S'
# Default log fmt
log_fmt="[<levelname>] [<asctime>] <message>"
# Default log color
log_color=('red' 'yellow' 'green' 'cyan')
# Support colors
support_colors='red yellow blue white cyan gray purple green'
# log_syslog defined, syslog enabled and log_syslog value as  syslog tag
# log_syslog="mysyslog"

# {{ LOG functions start

# Print log messages
# $1: Log level
# $2: C style printf fmt
# $3: C style printf arguments
do_log() {
    local level=$1
    local msg="$2"
    local fmt="${log_fmt}"

    if [ $level -gt $log_level ]; then
        return
    fi

    fmt="${fmt//<levelname>/${LOG_LEVELNAMES[$level]}}"
    fmt="${fmt//<asctime>/$(date +"$date_fmt")}"
    fmt="${fmt//<message>/$msg}"
    defined log_syslog && {
        shift 2 && ${log_color[level]:-printf} "☠️ $fmt" "$@" | logger -t "${log_syslog:-shell_log}"
    } || {
        shift 2 && ${log_color[level]:-printf} "☠️ $fmt" "$@" >&2
    }
}

debug_msg() {
    local fmt=$1
    shift && do_log $LOG_DEBUG "$fmt" "$@"
}

info_msg() {
    local fmt=$1
    shift && do_log $LOG_INFO "$fmt" "$@"
}

warn_msg() {
    local fmt=$1
    shift && do_log $LOG_WARNING "$fmt" "$@"
}

error_msg() {
    local fmt=$1
    shift && do_log $LOG_ERROR "$fmt" "$@"
}

# echo "$_out"|vinfo_msg
vinfo_msg() {
    while IFS='\n' read line || [ -n "$line" ]; do
        info_msg "$line\n"
    done
}

verror_msg() {
    while IFS='\n' read line || [ -n "$line" ]; do
        error_msg "$line\n"
    done
}

exit_msg() {
    error_msg "$@"
    exit 1
}

# LOG functions end }}

# Colorful print start {{

red() {
    defined QUIET && return
    local fmt=$1
    stderr_is_terminal && fmt="\033[1;31m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
}

green() {
    defined QUIET && return
    local fmt=$1
    stderr_is_terminal && fmt="\033[1;32m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
}

gray() {
    defined QUIET && return
    local fmt=$1
    stderr_is_terminal && fmt="\033[1;37m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
}

yellow() {
    defined QUIET && return
    local fmt=$1
    stderr_is_terminal && fmt="\033[1;33m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
}

blue() {
    defined QUIET && return
    local fmt=$1
    stderr_is_terminal && fmt="\033[1;34m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
}

cyan() {
    defined QUIET && return
    local fmt=$1
    stderr_is_terminal && fmt="\033[1;36m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
}

purple() {
    defined QUIET && return
    local fmt=$1
    stderr_is_terminal && fmt="\033[1;35m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
}

white() {
    defined QUIET && return
    local fmt=$1
    stderr_is_terminal && fmt="\033[1;38m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
}

# Colorful print end }}

# {{ Log set functions

# Set default log level
set_loglevel() {
    if echo "$1" | grep -qE "^[0-9]+$"; then
        log_level="$1"
    fi
}

# Set log format
set_logfmt() {
    if [ -n "$1" ]; then
        log_fmt="$1"
    fi
}

# Set date format, see 'man date'
set_datefmt() {
    if [ -n "$1" ]; then
        date_fmt="$1"
    fi
}

# Set log colors
set_logcolor() {
    local len=$#

    for (( i=0; i<$len; i++ )); do
        if echo "$support_colors" | grep -wq "$1"
        then
            log_color[$i]=$1
        else
            log_color[$i]=''
        fi
        shift
    done
}

# Disable colorful log
disable_color() {
    set_logcolor '' '' '' ''
}

# Log set functions }}

truecmd() {
    type -P $1
}

require() {
    local cmd=
    for cmd in $@ ; do
        command -v "${cmd}" &> /dev/null || exit_msg "require $cmd\n"
        #[ "$(command -v "$cmd")" ] || exit_msg "require $cmd\n"
    done
}

debugshell() {
    safe_echo "This is a debug shell (${1:-})."
    sh || true
    #PS1='(initramfs) ' sh -i </dev/console >/dev/console 2>&1
}

run_scripts() {
    local i= initdir=${1}
    [ ! -d "${initdir}" ] && return
    shift
    for i in ${initdir}/*; do
       # . "${initdir}/$i"
       cat "${initdir}/$i" | try
    done
}

#******************************************************************************
# try: Execute a command with error checking.  Note that when using this, if a piped
# command is used, the '|' must be escaped with '\' when calling try (i.e.
# "try ls \| less").
# Examples:
#  try my_command ${args} || return ${?}
#  try echo "log" \> log
#  cmds="
#    touch log
#    exit 0
#  "
#  try <<< $cmds
#  echo "$cmds" | try
#  cat <<EOF | try
#    echo hello >> log
#    exit 1
#  EOF
#  echo -n ${cli_prikey} | try wg pubkey
#  try "bash -s" <<EOF
#      ifconfig
#      start-stop-daemon --start --quiet --background --exec '/sbin/zebra'
#  EOF
#  #########################
#  BUG: when DRYRUN defined
#  DRYRUN: echo 1.1.1.1/24 dev
#  2.2.2.2/32,
#  while read -rd "," _lval && [ -n "${_lval}" ]; do
#      try "echo ${_lval} dev"
#  done <<< "1.1.1.1/24,2.2.2.2/32,"
#      0</dev/null try "echo ${_lval} dev" # can fix bug :(
#******************************************************************************
try() {
    # stdin is redirect and has parm, so stdin is not cmd stream!!
    local cmds="${@:-$(cat)}"
    local cmd_size=-60.60 retval=
    defined DRYRUN && { blue>&2 "DRYRUN: ";purple>&2 "$cmds\n"; stdin_is_terminal || cat >&2; return 0; }
    stderr_is_terminal || cmd_size=    #stderr is redirect show all cmd
    blue>&2 "Begin: ";purple>&2 "%${cmd_size}s." "$cmds"
    __ret_out= __ret_err= __ret_rc=0
    # eval -- "$( ($@ ; exit $?) \
    eval -- "$( (eval "$cmds";exit $?;) \
        2> >(__ret_err=$(cat); typeset -p __ret_err;) \
        1> >(__ret_out=$(cat); typeset -p __ret_out;); __ret_rc=$?; typeset -p __ret_rc; )"
    [ ${__ret_rc} = 0 ] && green>&2 " done.\n"
    [ ${__ret_rc} = 0 ] || {
        local cmd_func="" #"${FUNCNAME[1]}"
        for (( idx=${#FUNCNAME[@]}-1 ; idx>=1 ; idx-- )) ; do
            cmd_func+="${FUNCNAME[idx]} "
        done
        local cmd_line="${BASH_LINENO[1]}"
        red>&2 " failed(${cmd_func}:${cmd_line} [${__ret_rc}]).\n"
    }
    [ -z "${__ret_out}" ] || cat <<< "${__ret_out}"
    [ -z "${__ret_err}" ] || cat >&2 <<< "${__ret_err}"
    retval=${__ret_rc}
    unset __ret_out __ret_err __ret_rc
    return ${retval}
}

# undo command
# add_undo ls /home \> /root/cat
# add_undo "cat /etc/rc.local > /root/333aa"
# run_undo
rollback_cmds=()
run_undo() {
    local cmd= idx=
    [ ${#rollback_cmds[@]} -gt 0 ] || return 0
    # Run all "undo" commands if any.
    for (( idx=${#rollback_cmds[@]}-1 ; idx>=0 ; idx-- )) ; do
        cmd="${rollback_cmds[idx]}"
        purple "UNDO -> "
        try "$(eval printf '%s' "$cmd")" || true
    done
    rollback_cmds=()
    return 0
}
add_undo() {
    local cmd="$(printf '%q ' "$*")"
    array_append rollback_cmds "$cmd"
    return 0
}
## Tests if a variable is defined.
## @param variable Variable to test.
## @retval 0 if the variable is defined.
## @retval 1 in others cases.
defined() {
    [[ "${!1-X}" == "${!1-Y}" ]]
}

function_exists() {
    declare -f -F $1 >/dev/null
    return $?
}

directory_exists() {
    [ -d "$1" ]
}

link_exists() {
    [ -h "$1" ]
}

file_exists() {
    [ -e "$1" ]
}

regular_file_exists() {
    [ -f "$1" ]
}

device_exists() {
    [ -b "$1" ]
}

is_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

to_lower() {
    echo "${*,,}"
    #echo "$1" | tr '[:upper:]' '[:lower:]'
}

to_upper() {
    echo "${*^^}"
    #echo "$1" | tr '[:lower:]' '[:upper:]'
}
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}
# returns OK if $1 contains $2 at the beginning
str_starts() {
    [ "${1#$2*}" != "$1" ]
}
# returns OK if $1 contains $2 at the end
str_ends() {
    [ "${1%*$2}" != "$1" ]
}
# returns OK if $1 contains $2
strstr() {
    [ "${1#*$2*}" != "$1" ]
}
# replaces all occurrences of 'search' in 'str' with 'replacement'
# str_replace str search replacement
# example:
# str_replace '  one two  three  ' ' ' '_'
str_replace() {
    local in="$1"; local s="$2"; local r="$3"
    local out=''

    while strstr "${in}" "$s"; do
        chop="${in%%$s*}"
        out="${out}${chop}$r"
        in="${in#*$s}"
    done
    echo "${out}${in}"
}

split() {
    # Usage: split "string" "delimiter"
    IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"
    safe_echo '%s' "${arr[@]}"
}

array_append() {
    local array=$1; shift
    local len=$(array_size "$array")
    for i in "$@"; do
        eval "$array[$len]=\"$i\""
        let len=len+1
    done
}

array_size() {
    eval "echo \"\${#$1[@]}\""
}
# when "${ids[@]}" give a space-separated string,
# "${ids[*]}" (with a star * instead of the at sign @)
# will render a string separated by the first character of $IFS.
array_print() {
    eval "printf '%s\n' \"\${$1[@]}\""
}

array_print_label() {
    eval "printf '%s\n' \"\${!$1[@]}\""
}

array_label_exist() {
    eval "[ \${$1[$2]+t} ]"
}

array_set() {
    eval "$1[$2]=\"$3\""
}

array_get() {
    eval "printf '%s' \"\${$1[$2]}\""
}

urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c" ;;
        esac
        encoded+="${o}"
    done
    safe_echo "${encoded}"
}

urldecode() {
    local string="${1}"
    local strlen=${#string}
    local decoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            % ) o=$(echo "0x${string:$(($pos+1)):2}" | xxd -r); pos=$(($pos + 2)) ;;
            * ) o="${c}" ;;
        esac
        decoded+="${o}"
    done
    safe_echo "${decoded}"
}

# echo "key=abc" | del_config "key" | add_config "test" "testval" | set_config "test" "abc"
set_config() {
    local CONF_DELM=${3:-=}
    sed "s/^\($1\s*${CONF_DELM}\s*\).*\$/\1$2/"
}

del_config() {
    local CONF_DELM=${2:-=}
    sed "/^\($1\s*${CONF_DELM}\s*\).*\$/d"
}

add_config() {
    local CONF_DELM=${3:-=}
    del_config "$1" "${CONF_DELM}"
    echo "$1${CONF_DELM}$2"
}

# ID=100
# ARR=(a b c)
# DIC=(key1=a key2=b key3=c)
# cat <<EOF | json --arg id "$ID"  --argjson val "$ID" '."id"=$id | ."val"=$val' | json ".dummy=\"mesg\""
# {"foo":"bar" }
# EOF
# json --arg id "$ID" -n '{"id": $id}' | json --arg ssid abc --arg pass 12333 '.connections[$ssid] = $pass'
# json_dict driver="xx" id="$ID" "${DIC[@]}" |  json ".fuck=111"
# json --arg path "mypath" \
#      --arg input "$(echo "$ID" | base64)" \
#      --argjson arr "$(json_array ${ARR[@]})" \
#      --argjson params "$(json_dict "${DIC[@]}")" \
#      -n '{"path": $path, "input-data": $input, "arr": $arr, "props": $params}'
# cat <<EOF | json .path=\"mypath\" | json .arr="$(json_array ${ARR[@]})" | json .props="$(json_dict "${DIC[@]}")"
# {
#     "foo" : "bar",
#     "path": 1,
#     "input-data": "$(echo $ID | base64)",
#     "arr": 1,
#     "props": 1
# }
# EOF
json() {
    jq -cM "$@"
}

json_array() {
    for i in "$@"; do
        jq -cMn --arg arg "${i}" '$arg'
    done | jq -cMs .
}

json_dict() {
    local delm="="
    for i in "$@"; do
        jq -cMn --arg val "${i#*${delm}}" '{"'${i%%${delm}*}'": $val}'
    done | jq -cMs 'add // {}'
}

# {
#     "partitions": {
#         "boot_size": "67108864"
#     },
#     "debian": {
#         "release": "wheezy",
#         "packages": [ "openssh-server1", "openssh-server2", "openssh-server3" ]
#     }
# }
# json_config ".debian.packages[]" conf.json
# cat conf.json | json_config ".debian.packages[]"
# json_config ".debian.packages[]" <<< "$(cat conf.json)"
# get all keys
# json_config "keys[]" <<< "$(cat conf.json)"
# while IFS='' read -r line; do
#     echo $line
# done < <(json_config "keys[]" conf.json)
# mapfile -t arr < <(json_config "keys[]" conf.json) # bash 4+
# json_config "keys_unsorted | @sh" conf.json
json_config() {
    local key=${1}
    local str=""
    [ $# = 1 ] && {
        str="$(cat)"
    } || {
        str="$(cat ${2:?json_config input err})"
    }
    jq -r "(${key})? // empty" <<< ${str}
}
# get second argument if first one not found
json_config_default() {
    local key=${1}
    local default=${2}
    local str=""
    [ $# = 2 ] && {
        str="$(cat)"
    } || {
        str="$(cat ${3:?json_config input err})"
    }
    jq -r '('${key}') // "'${default}'"' <<< ${str}
}

# Performs POST onto specified URL with content formatted as json
#$1 uri
#$2 json file (if input is to be read from stdin use: -)
#$3 user in case of https
#$4 password in case of https
rest_json_post() {
    if [ -z $3 ]; then
        #without -s curl could display some debug info
        curl -s -H "Accept:application/json" -H "Content-Type:application/json" -X POST -k -d @$2 $1
    else
        curl -s -H "Accept:application/json" -H "Content-Type:application/json" -X POST -u "$3":"$4" -k -d @$2 $1
    fi
}

# Performs GET
#$1 uri
#$2 user in case of https
#$3 password in case of https
rest_json_get() {
    if [ -z $2 ]; then
        curl -k -i -H "Accept: application/json" $1
    else
        curl -k -i -H "Accept: application/json" -u "$2":"$3" $1
    fi
}

gen_addrv4() {
    local mac=$(cat "/sys/class/net/$1/address")
    IFS=':'; set $mac; unset IFS
    [ "$6" = "ff" -o "$6" = "00" ] && set $1 $2 $3 $4 $5 "01"
    printf "10.%d.%d.%d" 0x$4 0x$5 0x$6
}

gen_addrv6() {
    local mac=$(cat "/sys/class/net/$1/address")
    IFS=':'; set $mac; unset IFS
    printf fdef:17a0:ffb1:300:$(printf %02x $((0x$1 ^ 2)))$2:${3}ff:fe$4:$5$6
}

ip2int() {
    local a b c d
    { IFS=. read a b c d; } <<< $1
    safe_echo $(((((((a << 8) | b) << 8) | c) << 8) | d))
}

int2ip() {
    safe_echo "$((${1}>>24&255)).$((${1}>>16&255)).$((${1}>>8&255)).$((${1}&255))"
}

is_ipv4() {
    echo "$1" | {
        IFS=. read a b c d
        test "$a" -ge 0 -a "$a" -le 255 \
             -a "$b" -ge 0 -a "$b" -le 255 \
             -a "$c" -ge 0 -a "$c" -le 255 \
             -a "$d" -ge 0 -a "$d" -le 255 \
             2> /dev/null
    } && return 0
    return 1
}
is_fqdn() {
    safe_echo "$1" | grep -Pq '(?=^.{4,255}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}\.?$)'
    return $?
}
is_ipv4_netmask() {
    is_ipv4 "$1" || return 1
    IFS='.' read -r ipb[1] ipb[2] ipb[3] ipb[4] <<< "$1"
    local -r list_msb='0 128 192 224 240 248 252 254'
    for i in {1,2,3,4}; do
        if [[ ${rest_to_zero:-0} = 1 ]]; then
            [[ ${ipb[i]} -eq 0 ]] || return 1
        else
            if [[ $list_msb =~ (^|[[:space:]])${ipb[i]}($|[[:space:]]) ]]; then
                local -r rest_to_zero=1
            elif [[ ${ipb[i]} -eq 255 ]]; then
                continue
            else
                return 1
            fi
        fi
    done
    return 0
}
is_ipv4_cidr() {
    local -r regex='^[[:digit:]]{1,2}$'
    [[ $1 =~ $regex ]] || return 1
    [ "$1" -gt 32 ] || [ "$1" -lt 0 ] && return 1
    return 0
}
is_ipv4_subnet() {
    IFS='/' read -r tip tmask <<< "$1"
    is_ipv4_cidr "$tmask" || return 1
    is_ipv4 "$tip" || return 1
    return 0
}
get_ipv4_network() {
    is_ipv4 "$1" || return 1
    is_ipv4_netmask "$2" || return 1
    IFS='.' read -r ipb1 ipb2 ipb3 ipb4 <<< "$1"
    IFS='.' read -r mb1 mb2 mb3 mb4 <<< "$2"
    safe_echo "$((ipb1 & mb1)).$((ipb2 & mb2)).$((ipb3 & mb3)).$((ipb4 & mb4))"
}
get_ipv4_broadcast() {
    is_ipv4 "$1" || return 1
    is_ipv4_netmask "$2" || return 1
    IFS='.' read -r ipb1 ipb2 ipb3 ipb4 <<< "$1"
    IFS='.' read -r mb1 mb2 mb3 mb4 <<< "$2"
    nmb1=$((mb1 ^ 255))
    nmb2=$((mb2 ^ 255))
    nmb3=$((mb3 ^ 255))
    nmb4=$((mb4 ^ 255))
    safe_echo "$((ipb1 | nmb1)).$((ipb2 | nmb2)).$((ipb3 | nmb3)).$((ipb4 | nmb4))"
}
mask2cidr() {
    is_ipv4_netmask "$1" || return 1
    local x=${1##*255.}
    set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) "${x%%.*}"
    x=${1%%$3*}
    safe_echo $(( $2 + (${#x}/4) ))
}
cidr2mask() {
    is_ipv4_cidr "$1" || return 1
    local i mask=""
    local full_octets=$(($1/8))
    local partial_octet=$(($1%8))
    for ((i=0;i<4;i+=1)); do
        if [ $i -lt $full_octets ]; then
            mask+=255
        elif [ $i -eq $full_octets ]; then
            mask+=$((256 - 2**(8-partial_octet)))
        else
            mask+=0
        fi

        test $i -lt 3 && mask+=.
    done
    safe_echo $mask
}
if ([ "$0" = "$BASH_SOURCE" ] || ! [ -n "$BASH_SOURCE" ]);
then
    list_func
fi
