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

dummy() { :; }

list_func() {
    #function_name startwith _ is private usage!
    typeset -f | awk '/ \(\) $/ && !/^main / {print $1}' | grep -v "^_"
#    local fncs=$(declare -F -p | cut -d " " -f 3 | grep -v "^_")
#    echo $fncs
}

__M=$((1048576))
__G=$((1024*__M))
__T=$((1024*__G))
__P=$((1024*__T))
human_readable_disk_size() {
    local bytes=$1
    if [ $bytes -ge $__P ]; then echo $((bytes/__P))P; return; fi
    if [ $bytes -ge $__T ]; then echo $((bytes/__T))T; return; fi
    if [ $bytes -ge $__G ]; then echo $((bytes/__G))G; return; fi
    echo $((bytes/__M))M
}

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

get_ipaddr() {
    /sbin/ip -4 -br addr show ${1} | /bin/grep -Po "\\d+\\.\\d+\\.\\d+\\.\\d+"
}

##Usage: check_http_status 'http://www.example.com'
check_http_status() {
    local url=$1
    local status=$(curl -s -o /dev/null -w '%{http_code}' $url)
    echo $status
}

stdout_is_terminal() {
  [ -t 1 ]
}

is_user_root() {
    [ "$(id -u)" -eq 0 ]
}

# auto_su() {
#     self="$1"
#     # self="$(readlink -f "${BASH_SOURCE[0]}")"
#     # ARGS=( "$@" )
#     is_user_root() || exec sudo -p "Must be run as root. Please enter the password for %u to continue: " -- "$BASH" -- "$self" "${ARGS[@]}"
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

# echo "hello {{DISK_DEV}} \$(({{VAL}}*2))" | render_tpl2 vm
# same as render_tpl  #LHS='${' RHS='}'
# REPS default two LHS/RHS like {{ }}
# LHS='%' RHS='%'
SEQN="$(seq 1 ${REPS:-2})"
render_tpl2() {
    local str="$(cat)"
    local arr=$1
    for arg in $(array_print_label ${arr}) ; do
        local sub="${LHS:=$(printf '{%.0s' $SEQN)}${arg}${RHS:=$(printf '}%.0s' $SEQN)}"
        local val="$(array_get ${arr} "$arg")"
        str="${str//"$sub"/$val}"
    done
    cat <<< "$str"
}

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
    safe_echo -n "${item}"
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
    local cfg=${1};shift 1
    local allow_array=$1; shift 1
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
LOG_LEVELNAMES=('ERROR' 'WARNING' 'INFO' 'DEBUG')

# Global constants definition end }}

# Show log whose level less than this
log_level=3
# Default date fmt
date_fmt='%Y-%m-%d %H:%M:%S'
# Default log fmt
log_fmt="[<levelname>] [<asctime>] <message>"
# Default log color
log_color=('red' 'yellow' 'green' '')
# Support colors
support_colors='red yellow blue white cyan gray purple green'

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
    shift 2 && ${log_color[level]:-printf} "☠️ $fmt" "$@"
} >&2

debug_msg() {
    local fmt=$1
    shift && do_log $LOG_DEBUG "$fmt" "$@"
} >&2

info_msg() {
    local fmt=$1
    shift && do_log $LOG_INFO "$fmt" "$@"
} >&2

warn_msg() {
    local fmt=$1
    shift && do_log $LOG_WARNING "$fmt" "$@"
} >&2

error_msg() {
    local fmt=$1
    shift && do_log $LOG_ERROR "$fmt" "$@"
} >&2

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
    local fmt=$1
    [[ -t 2 ]] && fmt="\033[1;31m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
} >&2

green() {
    local fmt=$1
    [[ -t 2 ]] && fmt="\033[1;32m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
} >&2

gray() {
    local fmt=$1
    [[ -t 2 ]] && fmt="\033[1;37m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
} >&2

yellow() {
    local fmt=$1
    [[ -t 2 ]] && fmt="\033[1;33m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
} >&2

blue() {
    local fmt=$1
    [[ -t 2 ]] && fmt="\033[1;34m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
} >&2

cyan() {
    local fmt=$1
    [[ -t 2 ]] && fmt="\033[1;36m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
} >&2

purple() {
    local fmt=$1
    [[ -t 2 ]] && fmt="\033[1;35m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
} >&2

white() {
    local fmt=$1
    [[ -t 2 ]] && fmt="\033[1;38m${fmt}\033[0m"
    shift && printf "${fmt}" "$@"
} >&2

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
##################################################
run_scripts() {
    local i= initdir=${1}
    [ ! -d "${initdir}" ] && return

    shift
    for i in ${initdir}/*; do
        . "${initdir}/$i"
    done
}
##################################################
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

#******************************************************************************
# try: Execute a command with error checking.  Note that when using this, if a piped
# command is used, the '|' must be escaped with '\' when calling try (i.e.
# "try ls \| less").
# Examples:
#  try my_command ${args} || return ${?}
#  try --run my_command ${args} || return ${?}
#******************************************************************************
try() {
    local rc=0
    local cmd_size=-60.60
    [ ${DRYRUN:-0} = 0 ] || { safe_echo "EXECUTE $*" >&2; return 0; }
    [[ -t 2 ]] || cmd_size=    #stderr is redirect show all cmd
    [ ${QUIET:-0} = 0 ] && blue "Begin: %${cmd_size}s." "$*" >&2
    local result=$(eval $@ 2>&1) || rc=$?
    [ $rc = 0 ] && { [ ${QUIET:-0} = 0 ] && green " done.\n" >&2; printf "%s" "$result"; }
    [ $rc = 0 ] || {
        local cmd_func="" #"${FUNCNAME[1]}"
        for (( idx=${#FUNCNAME[@]}-1 ; idx>=1 ; idx-- )) ; do
            cmd_func+="${FUNCNAME[idx]} "
        done
        local cmd_line="${BASH_LINENO[1]}"
        [ ${QUIET:-0} = 0 ] && red " failed(${cmd_func}:${cmd_line} [$rc]).\n" >&2
        printf "%s\n" "$result" | verror_msg
    }
    return $rc
}
# try() {
#     local cmd
#     local __try_out
#     local ret
#     local cmd_size=-60.60
#     # Execute the command and fail if it does not return zero.
#     [[ -t 2 ]] || cmd_size=    #stderr is redirect show all cmd
#     set +o errexit
#     [[ "${1:-}" == "--run" ]] && {
#         shift
#         cmd="${*}"
#         [[ ${QUIET:-0} = 0 ]] && blue "Begin: %${cmd_size}s." "${cmd}" >&2
#         __try_out=$(${DRYRUN:+echo }${cmd} 2>&1)
#     } || {
#         cmd="${*}"
#         [[ ${QUIET:-0} = 0 ]] && blue "Begin: %${cmd_size}s." "${cmd}" >&2
#         __try_out=$(eval "${DRYRUN:+echo }${cmd}" 2>&1)
#     }
#     ret="$?"
#     #tput cuu1
#     if [ "$ret" == "0" ]; then
#         [[ ${QUIET:-0} = 0 ]] && green "${DRYRUN:+${cmd}} done.\\n" >&2
#         [[ -z "${__try_out}" ]] || printf "%s\n" "${__try_out}"
#     else
#         [[ ${QUIET:-0} = 0 ]] && red " failed($ret).\\n" >&2
#         error_msg "%s\\n%s\\n" "${cmd}" "${__try_out}" >&2
#     fi
#     set -o errexit
#     return "$ret"
# }

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
        [[ ${QUIET:-0} = 0 ]] && purple "UNDO -> "
        ${DRYRUN:+echo } try "$(eval printf '%s' "$cmd")" || true
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
  local exit_code=1
  if [ $# -ge 1 ]; then
    local param="${1}"
    grep --color=never -E -x -q '\-?[1-9]{1}[0-9]*' <<< "${param}" 1>/dev/null 2>/dev/null
    exit_code=$?
  fi
  return $exit_code
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
    echo "${1}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
string_ends_with() {
    # Usage: string_ends_wit hello lo
    [[ "${1}" == *${2} ]]
}
string_regex() {
    # Usage: string_regex "string" "regex"
    [[ $1 =~ $2 ]] && printf '%s\n' "${BASH_REMATCH[1]}"
}
string_starts_with() {
    # Usage: string_starts_with hello he
    [[ "${1}" == ${2}* ]]
}
string_contains() {
    # Usage: string_contains hello he
    [[ "${1}" == *${2}* ]]
}

split() {
    # Usage: split "string" "delimiter"
    IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"
    printf '%s\n' "${arr[@]}"
}

array_append() {
    local array=$1; shift 1
    local len=$(array_size "$array")
    for i in "$@"; do
        eval "$array[$len]=\"$i\""
        let len=len+1
    done
}

array_size() {
    eval "echo \"\${#$1[@]}\""
}

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

str_replace() {
    local ORIG="$1"
    local DEST="$2"
    local DATA="$3"

    safe_echo "${DATA//$ORIG/$DEST}"
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

# Use this to set the new config value, needs 2 parameters.
CONF_DELM='='
# echo "key=abc" | del_config "key" | add_config "test" "testval" | set_config "test" "abc"
set_config() {
    sed "s/^\($1\s*${CONF_DELM}\s*\).*\$/\1$2/"
}

del_config() {
    sed "/^\($1\s*${CONF_DELM}\s*\).*\$/d"
}

add_config() {
    del_config "$1"
    echo "$1${CONF_DELM}$2"
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

# parse simple json loaded from standard input
# $1 json field
json_parse() {
    python -c "import sys, json; print json.load(sys.stdin)[\"$1\"]"
}

addr4() {
  local mac=$(cat "/sys/class/net/$1/address")
  IFS=':'; set $mac; unset IFS
  [ "$6" = "ff" -o "$6" = "00" ] && set $1 $2 $3 $4 $5 "01"
  printf "10.%d.%d.%d" 0x$4 0x$5 0x$6
}

addr6() {
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

netmask() {
    local mask=$((0xffffffff << (32 - $1))); shift
    int2ip $mask
}

is_ipv4() {
    local -r regex='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    [[ $1 =~ $regex ]]
    return $?
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

return 0

