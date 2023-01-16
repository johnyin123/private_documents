#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("8c95c94[2023-01-12T10:01:25+08:00]:tpl_pack.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} <src directory> <dest file name>
        -c|--comp   <comp>  select <comp> compression
            Compressors available: like mksquashfs
                gzip (default)
                lzma
                lzo
                lz4
                xz
                zstd
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
  1. mydir=<your place>
  2. mkdir -p \${mydir}/overlay/upper \${mydir}/overlay/work \${mydir}/overlay/lower \${mydir}/newdir
  3. mount -o loop <your tpl> \${mydir}/overlay/lower
  4. mount -t overlay overlay -olowerdir=\${mydir}/overlay/lower,upperdir=\${mydir}/overlay/upper,workdir=\${mydir}/overlay/work \${mydir}/newdir
  5. chroot \${mydir}/newdir
EOF
    exit 1
}
main() {
    local comp=""
    local opt_short="c:"
    local opt_long="comp:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --comp)    shift; comp=${1}; shift;;
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
    require mksquashfs
    local src=${1:-}
    local dst=${2:-}
    [ -z "${src}" ] && usage "source directory must input"
    [ -z "${dst}" ] && usage "output tpl filename must input"
    info_msg "create template ${src} ==> ${dst}\n"
    try mksquashfs ${src} ${dst} ${comp:+-comp ${comp}} || true
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
