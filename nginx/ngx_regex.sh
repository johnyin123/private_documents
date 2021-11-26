#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2021-11-26T08:01:12+08:00]:ngx_regex.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -t|--testval   <str>   *  value for test
        -r|--regex     <regex> *  regex
        -i|--casesensitive        casesensitive, default false
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        NGINX Regular Expression Tester
        Exam:
           ${SCRIPTNAME} -r '^/(?<port>123[0-9])(?:/|$)' -t '/1231/a/b/c'
EOF
    exit 1
}

main() {
    NGX_URI="http://127.0.0.1:9000"
    local prefix='~' regex="" testval=""
    local opt_short="t:r:i"
    local opt_long="testval:,regex:,casesensitive,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -t | --testval)       shift; testval="${1}"; shift;;
            -r | --regex)         shift; regex="${1}"; shift;;
            -i | --casesensitive) shift; prefix='~*';;
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
    [ -z "${regex}" ] || [ -z "${testval}" ] && usage "need regex, testval"
    is_user_root || exit_msg "root user need!!\n"
    require pidof nginx curl
    cat <<EOF > ${DIRNAME}/map_regex_tester.conf
# If the regex is in quotes, the ~ or ~* needs to go inside
map \$variable \$value {
    ${prefix}${regex} "Map match. Value set to: ${testval}";
    default          "Map not match";
}
server {
    listen 127.0.0.1:9000;
    set \$variable "${testval}";
    location / {
        return 200 "\$value\\n";
    }
}
EOF
    cat <<EOF > ${DIRNAME}/loc_regex_tester.conf
server {
    listen 127.0.0.1:9001;
    location ${prefix} ${regex} {
        return 200 "Location match\\n";
    }
}
EOF
    # link_exists /etc/nginx/http-enabled/regex_tester.conf 
    rm -f /etc/nginx/http-enabled/map_regex_tester.conf && ln -s ${DIRNAME}/map_regex_tester.conf /etc/nginx/http-enabled/map_regex_tester.conf
    rm -f /etc/nginx/http-enabled/loc_regex_tester.conf && ln -s ${DIRNAME}/loc_regex_tester.conf /etc/nginx/http-enabled/loc_regex_tester.conf
    nginx -t 2>&1 && {
        pidof nginx &>/dev/null || nginx
        nginx -s reload
        sleep 1
        info_msg "MAP REGEX TEST\n"
        curl http://127.0.0.1:9000/
        info_msg "LOCATION REGEX TEST\n"
        curl http://127.0.0.1:9000/${testval}
    }
    return 0
}
main "$@"
