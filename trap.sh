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

###~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
# FUNCTION: EXIT_HANDLER
###~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##

function exit_handler ()
{
    local error_code="$?"
    test $error_code == 0 && return;
    _backtrace=$( backtrace 2 )
}
trap exit_handler EXIT                                                  # ! ! ! TRAP EXIT ! ! !
trap exit ERR                                                           # ! ! ! TRAP ERR ! ! !

# FUNCTION: BACKTRACE
function backtrace
{
    local _start_from_=0

    local params=( "$@" )
    if (( "${#params[@]}" >= "1" ))
        then
            _start_from_="$1"
    fi

    local i=0
    local first=false
    while caller $i > /dev/null
    do
        if test -n "$_start_from_" && (( "$i" + 1   >= "$_start_from_" ))
            then
                if test "$first" == false
                    then
                        echo "BACKTRACE IS:"
                        first=true
                fi
                caller $i
        fi
        let "i=i+1"
    done
}

return 0
