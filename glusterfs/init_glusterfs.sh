#!/usr/bin/env bash
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2022-08-01T09:08:13+08:00]:init_glusterfs.sh")
################################################################################
add_nodes() {
    local volname=${1}
    local brick=${2}
    gluster peer probe ${brick%:*}
    gluster volume add-brick "${vilname}" "${brick}"
    gluster volume info
    gluster volume rebalance "${vilname}" fix-layout start
    # gluster volume status
}

init_node() {
    local volname=${1}
    local replica=${2}
    shift 2 || { echo "brick no found"; return 1; }
    local brick=""
    systemctl enable glusterd.service --now
    for brick in "$@"; do
        gluster peer probe "${brick%:*}"
    done
    gluster peer status
    gluster volume create "${volname}" replica ${replica} "$@" force
    gluster volume start "${volname}"
    gluster volume info
    # gluster volume set "${volname}" nfs.disable on
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} <options> <brick1> <brick2> ...
              brick: srv1:/store
        -v|--vol     <str> *  glusterfs volumn name
        -r|--replica <int>    default 2
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
      Install: 
        apt -y install gnupg && wget -q -O- 'https://download.gluster.org/pub/gluster/glusterfs/10/rsa.pub' |
            gpg --dearmor > /etc/apt/trusted.gpg.d/gluster-archive-keyring.gpg
        apt -y install apt-transport-https
        echo deb [arch=amd64] https://download.gluster.org/pub/gluster/glusterfs/10/LATEST/Debian/bullseye/amd64/apt bullseye main > /etc/apt/sources.list.d/gluster.list 
        apt update && apt -y install [ glusterfs-server | glusterfs-client ]
        mount -t glusterfs node1:/vol /mnt
        echo "node1:/vol /mnt glusterfs defaults 0 1" >> /etc/fstab

EOF
    exit 1
}
main() {
    local volname="" replica=2
    local opt_short="v:r:"
    local opt_long="vol:,replica:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -v | --vol)     shift; volname=${1}; shift;;
            -r | --replica) shift; replica=${1}; shift;;
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
    [ -z "${volname}" ] && usage "need volname"
    ((replica < 2)) && usage "replica >=2"
    (($# < 2)) && usage "at least 2 brick"
    init_node "${volname}" $replica $@
    return 0
}
main "$@"
