# TO BE SOURCED ONLY ONCE:
if [ -z ${__mylib_inc+x} ]; then
    __mylib_inc=1
else
    return 0
fi

# MAIN CODE:
###~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##

# Disable unicode.
LC_ALL=C
LANG=C

set -o pipefail  # trace ERR through pipes
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

# taken from https://gist.github.com/aguy/2359833
# ------------------------------------------------
# trap 'trapexit $? $LINENO' EXIT
# trapexit() {
#   echo "$(date) $(hostname) $0: EXIT on line $2 (exit status $1)"
# }

trap 'traperror $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

traperror () {
    local err=$1 # error status
    local line=$2 # LINENO
    local linecallfunc=$3
    local command="$4"
    local funcstack="$5"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $(hostname) $0: ERROR '$command' failed line $line - exited $err - in ${funcstack}:$linecallfunc" 
    # echo "'$command' failed at line $line - exited with status: $err"| mail -s "ERROR: $0 on $(hostname) at $(date)"
}
return 0
