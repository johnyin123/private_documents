#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("0edc555[2022-01-18T09:33:57+08:00]:ssl.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -i|--init   <str> *  init ca, sign a server cert with DN=<str>
        -c|--client <str>  * create client cert keys
        --caroot             CA root(default ${DIRNAME}/ca)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
            apt -y install gnutls-bin
            yum -y install gnutls-utils
EOF
    exit 1
}

init_ca() {
    local caroot=${1}
    local dn=${2}
    [ -d "${caroot}" ] && return 1
    try mkdir -p ${caroot}
    info_msg "generate ca\n"
    cat << EOF | try tee ${caroot}/ca.info
cn = self sign root ca
ca
cert_signing_key
expiration_days = $((365*5))
EOF
    try certtool --generate-privkey --bits=2048 --outfile ${caroot}/ca.key
    try certtool --generate-self-signed --load-privkey ${caroot}/ca.key \
        --template ${caroot}/ca.info \
        --outfile ${caroot}/ca.pem
    try certtool -i --infile=${caroot}/ca.pem || true
    #openssl x509 -text -noout -in ${caroot}/ca.pem || true
    info_msg "gen ca server cert\n"
    cat << EOF | try tee ${caroot}/${dn}.info
organization = silf sign server
cn = ${dn}
signing_key
expiration_days = $((365*5))
EOF
    try certtool --generate-privkey --bits=2048 --outfile ${caroot}/${dn}.key
    try certtool --generate-certificate --load-privkey ${caroot}/${dn}.key \
        --load-ca-certificate ${caroot}/ca.pem \
        --load-ca-privkey ${caroot}/ca.key \
        --template ${caroot}/${dn}.info \
        --outfile ${caroot}/${dn}.pem
    info_msg "generate dh 2048\n"
    try certtool --generate-dh-params --outfile ${caroot}/dh2048.pem --sec-param medium
    try "tar -C ${caroot} -cv ca.pem ${dn}.key ${dn}.pem dh2048.pem | gzip > ${caroot}/${dn}.tar.gz"
}

gen_clent_cert() {
    local caroot=${1}
    local cid=${2}
    [ -e "${caroot}/client_${cid}.info" ] && return 1
    cat << EOF | try tee ${caroot}/client_${cid}.info
organization = ${cid} 
cn = ${cid}
signing_key
EOF
    try certtool --generate-privkey --outfile ${caroot}/client_${cid}.key
    try certtool --generate-certificate --load-privkey ${caroot}/client_${cid}.key \
        --load-ca-certificate ${caroot}/ca.pem \
        --load-ca-privkey ${caroot}/ca.key \
        --template ${caroot}/client_${cid}.info \
        --outfile ${caroot}/client_${cid}.pem
    try "tar -C ${caroot} -cv ca.pem client_${cid}.key client_${cid}.pem | gzip > ${caroot}/${cid}.tar.gz"
    info_msg "${caroot}/${cid}.tar.gz --> TO CLIENT\n"
}

main() {
    local init="" client=""  caroot="${DIRNAME}/ca"
    local opt_short="i:c:"
    local opt_long="init:,client:,caroot:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -i | --init)    shift; init=${1}; shift;;
            -c | --client)  shift; client=${1}; shift;;
            --caroot)       shift; caroot=${1}; shift;;
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
    [ -z "${init}" ] || {
        info_msg "install package\n"
        init_ca "${caroot}" "${init}"
    }
    [ -z "${client}" ] || {
        info_msg "generate client [${client}] cert\n"
        gen_clent_cert "${caroot}" "${client}" || {
            retval=$?
            error_msg "generate client [${client}] cert error[${retval}]\n"
        }
    }
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
