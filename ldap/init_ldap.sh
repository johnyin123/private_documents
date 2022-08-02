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
VERSION+=("9fe4f8d[2022-08-02T12:27:13+08:00]:init_ldap.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
MANAGER=${MANAGER:-admin}
MGR_PWD=password

change_ldap_passwd() {
    local passwd=${1}
:<<'__EOF'
    cat<<EOF >changerootpw.ldif
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $(slappasswd -n -s ${passwd}| base64 -w0)
EOF
    ldapadd -Y EXTERNAL -H ldapi:/// -f changerootpw.ldif
__EOF
    # backup, "-n 0" use database 0, which is the configuratiin directory.
    local bak_conf=$(mktemp -u)
    local bak_data=$(mktemp -u)
    slapcat -n 0 -l ${bak_conf}
    slapcat -n 1 -l ${bak_data}
    # change password
    sed -i -E \
        -e "s|^olcRootPW\s*:.*|olcRootPW:: $(slappasswd -n -s ${passwd}| base64 -w0)|g" \
        ${bak_conf}
    systemctl stop slapd
    rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/*
    slapadd -n 0 -F /etc/ldap/slapd.d -l ${bak_conf}
    slapadd -n 1 -F /etc/ldap/slapd.d -l ${bak_data}
    rm -f ${bak_conf} ${bak_data}
    chown -R openldap:openldap /etc/ldap/slapd.d*/ /var/lib/ldap/*
    slaptest -u
    systemctl start slapd
}

add_user() {
    local user=${1}
    local passwd=${2}
    local dc1=${3}
    local dc2=${4}
    local dc3=${5:-}
    # create new user
    # slapcat -n 0 | grep "olcObjectClasses:.*posixAccount"
    cat <<EOF >user_${user}.ldif
dn: uid=${user},ou=people,dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: ${user}
sn: ${user}
uid: 1000
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/${user}
userPassword: $(slappasswd -n -s ${passwd})

dn: cn=${user},ou=groups,dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}
objectClass: posixGroup
cn: ${user}
gidNumber: 1000
memberUid: ${user}
EOF
    ldapadd -x -D cn=${MANAGER},dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}} -w ${MGR_PWD} -v -f user_${user}.ldif
    ldapsearch -x cn=${user} -b dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}
}

setup_log() {
    local dc1=${1}
    local dc2=${2}
    local dc3=${3:-}
    echo "开启openldap日志访问功能"
    cat<<EOF >loglevel.ldif
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats
EOF
    ldapmodify -Y EXTERNAL -H ldapi:/// -f loglevel.ldif
    cat>>/etc/rsyslog.conf<<EOF
local4 .* /var/log/slapd.log
EOF
    systemctl restart rsyslog slapd
}

setup_multi_master_replication() {
    local srvid=${1} # specify uniq olcServerID number on each server, 101
    local peer=${2} # specify another LDAP server's URI, ldap://10.0.0.51:389/
    local dc1=${3}
    local dc2=${4}
    local dc3=${5:-}

    cat <<EOF>mod_syncprov.ldif
dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulePath: /usr/lib/ldap
olcModuleLoad: syncprov.la
EOF
    ldapadd -Y EXTERNAL -H ldapi:/// -f mod_syncprov.ldif
    cat <<EOF>syncprov.ldif
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpSessionLog: 100
EOF
    ldapadd -Y EXTERNAL -H ldapi:/// -f syncprov.ldif

  # [retry interval] [retry times] [interval of re-retry] [re-retry times]
  # retry="30 5 300 3"
    cat <<EOF>master01.ldif
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
  binddn="cn=${MANAGER},dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}"
  credentials=${MGR_PWD}
  searchbase="dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}"
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
    ldapmodify -Y EXTERNAL -H ldapi:/// -f master01.ldif

    return 0
}

setup_starttls() {
    local ca=${1}
    local cert=${2}
    local key=${3}
    local ssl_conf=$(mktemp -u)

    cat <<EOF >${ssl_conf}
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
    ldapmodify -Y EXTERNAL -H ldapi:/// -f ${ssl_conf}
    rm -f ${ssl_conf}
    systemctl restart slapd
}

init_ldap() {
    local dc1=${1}
    local dc2=${2}
    local dc3=${3:-}
    local bak_conf=$(mktemp -u)
    local bak_data=$(mktemp -u)
    slapcat -n 0 -l ${bak_conf}
    slapcat -n 1 -l ${bak_data}
    sed -i -E \
        -e ""s/dc\s*=.*/dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}/g \
        ${bak_conf}
    sed -i -E \
        -e "s/^o\s*:.*/o: ${dc1}${dc2:+.${dc2}}${dc3:+.${dc3}}/g" \
        -e "s/^dc\s*:.*/dc: ${dc1}/g" \
        -e "s/dc\s*=.*/dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}/g" \
        ${bak_data}
    systemctl stop slapd
    rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/*
    slapadd -n 0 -F /etc/ldap/slapd.d -l ${bak_conf}
    slapadd -n 1 -F /etc/ldap/slapd.d -l ${bak_data}
    rm -f ${bak_conf} ${bak_data}
    chown -R openldap:openldap /etc/ldap/slapd.d*/ /var/lib/ldap/*
    slaptest -u
    systemctl start slapd
    cat <<EOF > base.ldif
dn: ou=people,dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}
objectClass: organizationalUnit
ou: people

dn: ou=groups,dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}
objectClass: organizationalUnit
ou: groups
EOF
    echo "add user data!!!!"
    ldapadd -x -D cn=${MANAGER},dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}} -w ${MGR_PWD} -v -f base.ldif || return 1
    return 0
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
          env:
            MANAGER=admin
          init mode: --dc1 test --dc2 mail -p password <--ca ca.pem --cert /a.pem --key /a.key --srvid 104 --peer ldap://ip:389/>
          add user mode: --dc1 test --dc2 mail -p password -u user1 -u user2
        --dc1      *    <str>  dc1.dc2/dc1.dc2.dc3<sample.org/sample.org.cn>
        --dc1           <str>
        --dc1           <str>
        -p|--passwd     <str>  slapd manager password, <default:password>, init mode change to <str>
        -u|--uid        <str>  adduser mode uid in ldap, multi parameters
        --ca            <str>  ca file
        --cert          <str>  cert file
        --key           <str>  key file
        --srvid         <num>  multimaster mode uniq id on each server, 101
        --peer          <str>  multimaster mode other node url, ldap://ip:389/
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        # apt -y install slapd ldap-utils
        # dpkg-reconfigure slapd
        # test ssl
        openssl s_client -host <host> -port 389 -starttls ldap
        ldapsearch -x -b dc=example,dc=org -ZZ
        # delete user&group
        ldapdelete -x -W -D "cn=${MANAGER},dc=example,dc=org" "uid=testuser1,ou=People,dc=example,dc=com"
        ldapdelete -x -W -D "cn=${MANAGER},dc=example,dc=org" "cn=testuser1,ou=Group,dc=example,dc=com"
EOF
    exit 1
}
main() {
    local dc1="" dc2="" dc3="" ca="" cert="" key=""
    local uid=()
    local opt_short="p:u:"
    local opt_long="passwd:,dc1:,dc2:,dc3:,uid:,ca:,cert:,key:,srvid:,peer:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --dc1)          shift; dc1=${1}; shift;;
            --dc2)          shift; dc2=${1}; shift;;
            --dc3)          shift; dc3=${1}; shift;;
            --ca)           shift; ca=${1}; shift;;
            --cert)         shift; cert=${1}; shift;;
            --srvid)        shift; srvid=${1}; shift;;
            --peer)         shift; peer=${1}; shift;;
            --key)          shift; key=${1}; shift;;
            -p | --passwd)  shift; MGR_PWD=${1}; shift;;
            -u | --uid)     shift; uid+=(${1}); shift;;
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
    [ -z "${dc1}" ] && usage "dc1 must input"

    for _u in "${uid[@]}"; do
        echo "add uid <$_u: password>";
        add_user "$_u" "password" "${dc1}" "${dc2}" "${dc3}" || echo "**** add $_u failed"
    done
    ((${#uid[@]} > 0)) && { echo "Add user ALL OK"; return 0; }
    change_ldap_passwd "${MGR_PWD}"
    init_ldap "${dc1}" "${dc2}" "${dc3}" || { echo "some failed, run: dpkg-reconfigure slapd, and reinit slapd"; return 1; }
    [ -z "${ca}" ] || [ -z "${cert}" ] || [ -z "${key}" ] || setup_starttls "${ca}" "${cert}" "${key}"
    [ -z "${srvid}" ] || [ -z "${peer}" ] || setup_multi_master_replication "${srvid}" "${peer}" "${dc1}" "${dc2}" "${dc3}"
    echo "************ALL INIT OK ${TIMESPAN}"
    ldapsearch -LLL -x \
        -D cn=${MANAGER},dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}} \
        -w ${MGR_PWD} \
        -H ldap://0.0.0.0:389/ \
        -b dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}
    return 0
}
main "$@"
