##################################################
# print "$(convertsecs $TOTALTIME)"
# To compute the time it takes a script to run use tag the start and end times with
#   STARTTIME=$(date +"%s")
#   ENDTIME=$(date +"%s")
#   TOTALTIME=$(($ENDTIME-$STARTTIME))
# ------------------------------------------------------
convertsecs() {
  ((h=${1}/3600))
  ((m=(${1}%3600)/60))
  ((s=${1}%60))
  printf "%02d:%02d:%02d\n" $h $m $s
}
##################################################
readonly RED="\033[1;31m"
readonly GREEN="\033[1;32m"
readonly YELLOW="\033[1;33m"
readonly BLUE="\033[1;34m"
readonly ENDCLR="\033[0m"
_log_msg()
{
	if [ "${quiet:-n}" = "y" ]; then return; fi
	# shellcheck disable=SC2059
	printf "$@"
}

log_success_msg()
{
	_log_msg "${GREEN}Success:${ENDCLR} %s\\n" "$*"
}

log_failure_msg()
{
	_log_msg "${RED}Failure:${ENDCLR} %s\\n" "$*"
}

log_warning_msg()
{
	_log_msg "${YELLOW}Warning:${ENDCLR} %s\\n" "$*"
}
##################################################
run_scripts()
{
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
try ()
{
    CMD="${*}"
	# Execute the command and fail if it does not return zero.
    _log_msg "${BLUE}Begin:${ENDCLR} %-35s " "${CMD:0:29}..."
    RESULT=$(eval "${CMD}" 2>&1)
    ERROR="$?"
    #tput cuu1
    if [ "$ERROR" == "0" ]; then
    	_log_msg "${BLUE}done.${ENDCLR}\\n"
    else
        _log_msg "\033[5;49;39m${BLUE}failed($ERROR).${ENDCLR}\\n"
        _log_msg "${RESULT}\\n"
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
str_replace() {
    local ORIG="$1"
    local DEST="$2"
    local DATA="$3"

    echo "${DATA//$ORIG/$DEST}"
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
