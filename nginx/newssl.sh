#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("311056e[2022-02-15T15:49:59+08:00]:newssl.sh")
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
    # 吊销证书
        openssl ca -revoke <cert>
        openssl ca -gencrl -out "you.crl"
EOF
    exit 1
}

init_ca() {
    local caroot=${1}
    local dn=${2}
    [ -d "${caroot}" ] && return 1
    try mkdir -p ${caroot}
    info_msg "creating ca key\n"
    try openssl genrsa -out ${caroot}/ca.key 2048
    info_msg "creating ca cert\n"
    try openssl req -new -x509 -days $((365*5)) -key ${caroot}/ca.key \
        -out ${caroot}/ca.pem -utf8 -subj \"/C=CN/L=LN/O=${dn}/CN=self sign root ca\"
    try openssl x509 -text -noout -in ${caroot}/ca.pem
    info_msg "gen dh2048\n"
    try openssl dhparam -out ${caroot}/dh2048.pem 2048
}

gen_clent_cert() {
    local caroot=${1}
    local cid=${2}
    [ -e "${caroot}/${cid}.csr" ] && return 1
    info_msg "create key\n"
    try openssl genrsa -out ${caroot}/${cid}.key 2048
    info_msg "create certificate signing request (csr)\n"
    try openssl req -new -key ${caroot}/${cid}.key -out ${caroot}/${cid}.csr \
        -utf8 -subj \"/C=CN/L=LN/O=mycompany/CN=${cid}\"
    info_msg "signing our certificate with my ca"
    try openssl x509 -req -days $((365*5)) -in ${caroot}/${cid}.csr \
        -CA ${caroot}/ca.pem -CAkey ${caroot}/ca.key -CAcreateserial -out ${caroot}/${cid}.pem
    try openssl x509 -text -noout -in ${caroot}/${cid}.pem
    # info_msg "conver to broswer support format(p12).\n"
    convert_p12 ${caroot} ${cid}
    # try openssl pkcs12 -export -in ${caroot}/${cid}.pem -out ${caroot}/${cid}.p12 -inkey ${caroot}/${cid}.key
    try "tar -C ${caroot} -cv ca.pem ${cid}.key ${cid}.pem ${cid}.p12 | gzip > ${caroot}/${cid}.tar.gz"
    info_msg "${caroot}/${cid}.tar.gz --> TO CLIENT\n"
}

convert_p12() {
    local caroot=${1}
    local cid=${2}
    local pass="password"
    local username="$(openssl x509 -noout  -in ${caroot}/${cid}.pem -subject | sed -e 's;.*CN\s*=\s*;;' -e 's;/Em.*;;')"
    local caname="$(openssl x509 -noout  -in ${caroot}/ca.pem -subject | sed -e 's;.*CN\s*=\s*;;' -e 's;/Em.*;;')"
    try openssl pkcs12 \
        -export \
        -in "${caroot}/${cid}.pem" \
        -inkey "${caroot}/${cid}.key" \
        -certfile ${caroot}/ca.pem \
        -name \"$username\" \
        -caname \"$caname\" \
        -password pass:${pass} \
        -out ${caroot}/${cid}.p12
    try openssl pkcs12 -info -in ${caroot}/${cid}.p12 -passin pass:${pass} -passout pass:${pass}
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
        init_ca "${caroot}" "${init}" || exit_msg "${caroot} dir exists\n"
    }
    [ -z "${client}" ] || {
        info_msg "generate client [${client}] cert\n"
        gen_clent_cert "${caroot}" "${client}" || {
            retval=$?
            error_msg "generate client [${client}] cert error[${retval}]\n"
        }
        info_msg "conver to broswer support format.\n"
        info_msg "openssl pkcs12 -export -clcerts -in ${client}.pem -inkey ${client}.key -out ${client}.p12\n"
    }
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
