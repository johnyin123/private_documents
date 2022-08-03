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
VERSION+=("8c285ba[2022-08-03T07:07:52+08:00]:init_ldap.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
DEFAULT_ADD_USER_PASSWORD=${DEFAULT_ADD_USER_PASSWORD:-"Password"}
LOGFILE=""

change_ldap_mgr_passwd() {
    passwd=${1}
    PASS_HASH=$(slappasswd -n -s ${passwd})
    cat <<EOF |tee ${LOGFILE}| ldapmodify -d 256 -H ldapi:// -Q -Y EXTERNAL
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: ${PASS_HASH}
EOF
    echo -n "${PASS_HASH} => "
    slapcat -n 0 | grep olcRootPW: | awk '{ print $2}' | base64 -d
    echo
}

setup_log() {
    local dc1=${1}
    local dc2=${2}
    local dc3=${3:-}
    echo "****开启openldap日志访问功能" | tee ${LOGFILE}
    cat<<EOF |tee ${LOGFILE}| ldapmodify -Q -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats
EOF

    cat>>/etc/rsyslog.conf<<EOF
local4 .* /var/log/slapd.log
EOF
    systemctl restart rsyslog slapd
}

init_ldap() {
    # LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y slapd
    local passwd=${1}
    local domain=${2}
    local org="${3}"
    echo "****openldap dpkg-reconfigure" | tee ${LOGFILE}
cat <<EOF |tee ${LOGFILE}| debconf-set-selections
slapd slapd/password1 password ${passwd}
slapd slapd/password2 password ${passwd}
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/domain string ${domain}
slapd shared/organization string ${org}
slapd slapd/backend string MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
slapd slapd/dump_database select when needed
EOF
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure slapd
    slaptest -u
}

add_user() {
    local user=${1}
    local olcRootDN=${2}
    local olcSuffix=${3}
    local passwd=${4}
    # create new user
    # slapcat -n 0 | grep "olcObjectClasses:.*posixAccount"
    echo "****CREATE USER ${user}:${DEFAULT_ADD_USER_PASSWORD}"
    cat <<EOF |tee ${LOGFILE}| ldapadd -x -D ${olcRootDN} -w ${passwd}
dn: uid=${user},ou=people,${olcSuffix}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: ${user}
sn: ${user}
uid: 1000
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/${user}
userPassword: $(slappasswd -n -s ${DEFAULT_ADD_USER_PASSWORD})

dn: cn=${user},ou=groups,${olcSuffix}
objectClass: posixGroup
cn: ${user}
gidNumber: 1000
memberUid: ${user}
EOF
    ldapsearch -x cn=${user} -b ${olcSuffix}
}

setup_multi_master_replication() {
    local srvid=${1} # specify uniq olcServerID number on each server, 101
    local peer=${2} # specify another LDAP server's URI, ldap://10.0.0.51:389/
    local olcRootDN=${3}
    local olcSuffix=${4}
    local passwd=${5}
    echo "****setup multi_master replication.1" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapadd -Q -Y EXTERNAL -H ldapi:///
dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulePath: /usr/lib/ldap
olcModuleLoad: syncprov.la
EOF
    echo "****setup multi_master replication.2" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapadd -Q -Y EXTERNAL -H ldapi:///
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpSessionLog: 100
EOF

    # [retry interval] [retry times] [interval of re-retry] [re-retry times]
    # retry="30 5 300 3"
    echo "****setup multi_master replication.3" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapmodify -Q -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: ${srvid}

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncRepl
olcSyncRepl: rid=001
  provider=${peer}
  bindmethod=simple
  binddn="${olcRootDN}"
  credentials=${passwd}
  searchbase="${olcSuffix}"
  scope=sub
  schemachecking=on
  type=refreshAndPersist
  retry="30 5 300 3"
  interval=00:00:05:00
-
add: olcMirrorMode
olcMirrorMode: TRUE

dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
EOF
    return 0
}

setup_starttls() {
    local ca=${1}
    local cert=${2}
    local key=${3}
    echo "****setup tls" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapmodify -Q -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: ${ca}
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: ${cert}
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: ${key}
EOF
    # systemctl restart slapd
}

init_ldap_schema() {
    local olcRootDN=${1}
    local olcSuffix=${2}
    local passwd=${3}
    echo "****setup user schema" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapadd -x -D ${olcRootDN} -w "${passwd}"
dn: ou=people,${olcSuffix}
objectClass: organizationalUnit
ou: people

dn: ou=groups,${olcSuffix}
objectClass: organizationalUnit
ou: groups
EOF
    return 0
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
          init mode: -D sample.org -O "a b c" -p password <--ca ca.pem --cert /a.pem --key /a.key --srvid 104 --peer ldap://ip:389/>
          add user mode: -u user1 -u user2
        -D|--domain     <str>  domain, sample.org
        -O|--org        <str>  organization, "my company. ltd."
        -P|--passwd     <str>  slapd manager password
        -u|--uid        <str>  adduser mode uid in ldap, multi parameters
        --ca            <str>  ca file
        --cert          <str>  cert file
        --key           <str>  key file
        --srvid         <num>  multimaster mode uniq id on each server, 101
        --peer          <str>  multimaster mode other node url, ldap://ip:389/
        -q|--quiet
        -l|--log <str>  log file
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        # apt -y install slapd ldap-utils
        # dpkg-reconfigure slapd
        # dump ldif
            slapcat -n 0 -l conf.ldif
            slapcat -n 1 -l data.ldif
        # test ssl
        openssl s_client -host <host> -port 389 -starttls ldap
        ldapsearch -x -b dc=example,dc=org -ZZ
        # delete user&group
        ldapdelete -x -W -D "cn=admin,dc=example,dc=org" "uid=testuser1,ou=People,dc=example,dc=com"
        ldapdelete -x -W -D "cn=admin,dc=example,dc=org" "cn=testuser1,ou=Group,dc=example,dc=com"
EOF
    exit 1
}
main() {
    local _u="" olcRootDN="" olcSuffix=""
    local passwd="" domain="" org="" ca="/dummy" cert="" key="" servid="" peer=""
    local uid=()
    local opt_short="P:D:O:u:"
    local opt_long="passwd:,domain:,org:,ca:,cert:,key:,srvid:,peer:,uid:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -P | --passwd)  shift; passwd=${1}; shift;;
            -D | --domain)  shift; domain=${1}; shift;;
            -O | --org)     shift; org=${1}; shift;;
            --ca)           shift; ca=${1}; shift;;
            --cert)         shift; cert=${1}; shift;;
            --key)          shift; key=${1}; shift;;
            --srvid)        shift; srvid=${1}; shift;;
            --peer)         shift; peer=${1}; shift;;
            -u | --uid)     shift; uid+=(${1}); shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; LOGFILE="-a ${1}"; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    for _u in "${uid[@]}"; do
        echo "add uid <$_u: password>";
        add_user "$_u" "password" "" || echo "****ADD $_u failed" | tee ${LOGFILE}
    done
    ((${#uid[@]} > 0)) && { echo "****ADD USER ALL OK" | tee ${LOGFILE}; return 0; }
    [ -z "${passwd}" ] || [ -z "${domain}" ] || [ -z "${org}" ] || {
        init_ldap "${passwd}" "${domain}" "${org}"
        olcRootDN=$(slapcat -n 0 | grep -E -e "olcRootDN" | grep -v "cn=config" | awk '{print $2}')
        olcSuffix=$(slapcat -n 0  | grep "olcSuffix" | awk '{print $2}')
        init_ldap_schema "${olcRootDN}" "${olcSuffix}" "${passwd}"
        echo "****INIT OK ${TIMESPAN}" | tee ${LOGFILE}
    }
    [ -z "${ca}" ] || [ -z "${cert}" ] || [ -z "${key}" ] || {
        setup_starttls "${ca}" "${cert}" "${key}"
        echo "****INIT STARTTLS OK ${TIMESPAN}" | tee ${LOGFILE}
    }
    [ -z "${srvid}" ] || [ -z "${peer}" ] || [ -z "${passwd}" ] || {
        olcRootDN=$(slapcat -n 0 | grep -E -e "olcRootDN" | grep -v "cn=config" | awk '{print $2}')
        olcSuffix=$(slapcat -n 0  | grep "olcSuffix" | awk '{print $2}')
        setup_multi_master_replication "${srvid}" "${peer}" "${olcRootDN}" "${olcSuffix}" "${passwd}"
        echo "****INIT MULTI MASTER OK ${TIMESPAN}" | tee ${LOGFILE}
    }
    return 0
}
main "$@"
