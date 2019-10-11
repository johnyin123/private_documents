#!/bin/echo Warnning, this library must only be sourced! 
# TO BE SOURCED ONLY ONCE:
if [ -z ${__functions_inc+x} ]; then
    __functions_inc=1
else
    return 0
fi
# Disable unicode.
LC_ALL=C
LANG=C

set -o pipefail  # trace ERR through pipes
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
##################################################
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

    shift 2 && ${log_color[level]:-printf} "$fmt" "$@"
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
    return 1
}

exit_msg() {
    error_msg "$@"
    exit 1
}

# LOG functions end }}

# Colorful print start {{

red() {
    local fmt=$1
    shift && printf "\033[1;31m${fmt}\033[0m" "$@"
}

green() {
    local fmt=$1
    shift && printf "\033[1;32m${fmt}\033[0m" "$@"
}

gray() {
    local fmt=$1
    shift && printf "\033[1;37m${fmt}\033[0m" "$@"
}

yellow() {
    local fmt=$1
    shift && printf "\033[1;33m${fmt}\033[0m" "$@"
}

blue() {
    local fmt=$1
    shift && printf "\033[1;34m${fmt}\033[0m" "$@"
}

cyan() {
    local fmt=$1
    shift && printf "\033[1;36m${fmt}\033[0m" "$@"
}

purple() {
    local fmt=$1
    shift && printf "\033[1;35m${fmt}\033[0m" "$@"
}

white() {
    local fmt=$1
    shift && printf "\033[1;38m${fmt}\033[0m" "$@"
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
##################################################
run_scripts() {
    initdir=${1}
    [ ! -d "${initdir}" ] && return

    shift
    for i in ${initdir}/*; do
        . "${initdir}/$i"
    done
}
##################################################
#******************************************************************************
# try: Execute a command with error checking.  Note that when using this, if a piped
# command is used, the '|' must be escaped with '\' when calling try (i.e.
# "try ls \| less").
#******************************************************************************
try () {
    CMD="${*}"
    if [ "${DRYRUN:-0}" -eq 1 ] ; then
        echo $CMD
        return 0
    fi
    # Execute the command and fail if it does not return zero.
    [[ ${QUIET:-0} = 0 ]] && blue "Begin: %-35s " "${CMD:0:29}..."
    RESULT=$(eval "${CMD}" 2>&1)
    ERROR="$?"
    #tput cuu1
    if [ "$ERROR" == "0" ]; then
        [[ ${QUIET:-0} = 0 ]] && green "done.\\n"
    else
        [[ ${QUIET:-0} = 0 ]] && red "failed($ERROR).\\n"
        error_msg "%s\n" "${RESULT}"
    fi
    return "$ERROR"
}

directory_exists() {
    if [[ -d "$1" ]]; then
        return 0
    fi
    return 1
}

file_exists() {
    if [[ -f "$1" ]]; then
        return 0
    fi
    return 1
}

device_exists() {
    if [[ -b "$1" ]]; then
        return 0
    fi
    return 1
}

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
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

__array_append() {
    echo -n 'eval '
    echo -n "$1" # array name
    echo -n '=( "${'
    echo -n "$1"
    echo -n '[@]}" "'
    echo -n "$2" # item to append
    echo -n '" )'
}
__array_append_first() {
    echo -n 'eval '
    echo -n "$1" # array name
    echo -n '=( '
    echo -n "$2" # item to append
    echo -n ' )'
}
__array_len() {
    echo -n 'eval local '
    echo -n "$1" # variable name
    echo -n '=${#'
    echo -n "$2" # array name
    echo -n '[@]}'
}

array_append() {
    local array=$1; shift 1
    local len

    $(__array_len len "$array")

    if (( len == 0 )); then
        $(__array_append_first "$array" "$1" )
        shift 1
    fi

    local i
    for i in "$@"; do
        $(__array_append "$array" "$i")
    done
}

array_size() {
    local size

    $(__array_len size "$1")
    echo "$size"
}

array_print() {
    eval "printf '%s\n' \"\${$1[@]}\""
}

array_print_label() {
    eval "printf '%s\n' \"\${!$1[@]}\""
}

array_get() {
    eval "printf '%s' \"\${$1[$2]}\""
}

str_replace() {
    local ORIG="$1"
    local DEST="$2"
    local DATA="$3"

    echo "${DATA//$ORIG/$DEST}"
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

ip2int() {
    local a b c d
    { IFS=. read a b c d; } <<< $1
    echo $(((((((a << 8) | b) << 8) | c) << 8) | d))
}

int2ip() {
    local ui32=$1; shift
    local ip n
    for n in 1 2 3 4; do
        ip=$((ui32 & 0xff))${ip:+.}$ip
        ui32=$((ui32 >> 8))
    done
    echo $ip
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
    echo "$1" | grep -Pq '(?=^.{4,255}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}\.?$)'

    return $?
}
is_ipv4_netmask() {
    is_ipv4 "$1" || return 1

    IFS='.' read -r ipb[1] ipb[2] ipb[3] ipb[4] <<< "$1"

    local -r list_msb='0 128 192 224 240 248 252 254'

    for i in {1,2,3,4}; do
        if [[ $rest_to_zero ]]; then
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

    echo "$((ipb1 & mb1)).$((ipb2 & mb2)).$((ipb3 & mb3)).$((ipb4 & mb4))"
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

    echo "$((ipb1 | nmb1)).$((ipb2 | nmb2)).$((ipb3 | nmb3)).$((ipb4 | nmb4))"
}
mask2cidr() {
    is_ipv4_netmask "$1" || return 1

    local x=${1##*255.}
    set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) "${x%%.*}"
    x=${1%%$3*}
    echo $(( $2 + (${#x}/4) ))
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

    echo $mask
}

return 0

