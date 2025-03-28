#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("ce2b1c3[2024-03-29T14:43:54+08:00]:newssl.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
YEAR=${YEAR:-5}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env: YEAR=5, the ca&client years, default 5
        -i|--init   <str> *  init ca, sign a server cert with DN=<str>
        -c|--client <str>  * create client cert keys
        --ip        <ip>     client cert subjectAltName ip, multi input
        --caroot             CA root(default ${DIRNAME}/ca)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
            apt -y install gnutls-bin
            yum -y install gnutls-utils
    # 吊销证书, SEE: revoke.sh
        openssl ca -revoke <cert>
        openssl ca -gencrl -out "you.crl"
    # cer to pem
        openssl x509 -inform der -in certificate.cer -out certificate.pem
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
    try openssl req -new -x509 -days $((365*${YEAR})) -key ${caroot}/ca.key \
        -out ${caroot}/ca.pem -utf8 -subj \"/C=CN/L=LN/O=${dn}/CN=self sign root ca\"
    try openssl x509 -text -noout -in ${caroot}/ca.pem
    info_msg "gen dh2048\n"
    try openssl dhparam -out ${caroot}/dh2048.pem 2048
}

gen_client_cert() {
    local caroot=${1}
    local cid=${2}
    local ips=($(array_print ${3}))
    [ -e "${caroot}/${cid}.csr" ] && { error_msg "${caroot}/${cid} file exist!!!!\n"; return 1; }
    info_msg "create key\n"
    try openssl genrsa -out ${caroot}/${cid}.key 2048
    info_msg "create certificate signing request (csr)\n"
    try openssl req -new -key ${caroot}/${cid}.key -out ${caroot}/${cid}.csr \
        -utf8 -subj \"/C=CN/L=LN/O=mycompany/CN=${cid}\"
    info_msg "signing our certificate with my ca"
    echo -n "subjectAltName = DNS:${cid}" > extfile.cnf
    num=1
    for ipaddr in $(array_print ips); do
        echo -n ",IP.${num}:${ipaddr}" >> extfile.cnf
        let $((num++))
    done
    #  -extfile <(printf "${csr_conf} extendedKeyUsage = clientAuth\n")
    try openssl x509 -req -days $((365*${YEAR})) -in ${caroot}/${cid}.csr \
        -extfile extfile.cnf \
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

cert_get_subject_alt_name() {
  local cert=${1}
  local alt_name=$(openssl x509 -text -noout -in ${cert} | grep -A1 'Alternative' | tail -n1 | sed 's/[[:space:]]*Address//g')
  printf "${alt_name}\n"
}

# get subject from the old certificate
cert_get_subj() {
  local cert=${1}
  local subj=$(openssl x509 -text -noout -in ${cert}  | grep "Subject:" | sed 's/Subject:/\//g;s/\,/\//;s/[[:space:]]//g')
  printf "${subj}\n"
}

main() {
    local init="" client="" ips=(127.0.0.1) caroot="${DIRNAME}/ca"
    local opt_short="i:c:"
    local opt_long="init:,client:,caroot:,ip:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -i | --init)    shift; init=${1}; shift;;
            -c | --client)  shift; client=${1}; shift;;
            --ip)           shift; ips+=(${1}); shift;;
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
        gen_client_cert "${caroot}" "${client}" ips|| {
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
