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
VERSION+=("f4fbcd4[2022-08-09T12:56:01+08:00]:init_ldap.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
DEFAULT_ADD_USER_PASSWORD=${DEFAULT_ADD_USER_PASSWORD:-"password"}
LOGFILE=""
MAIL_GID=9999
change_ldap_mgr_passwd() {
    passwd=${1}
    PASS_HASH=$(slappasswd -n -s ${passwd})
    cat <<EOF |tee ${LOGFILE}| ldapmodify -d 256 -H ldapi:// -Q -Y EXTERNAL
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: ${PASS_HASH}
EOF
    echo -n "${PASS_HASH} => " | tee ${LOGFILE}
    slapcat -n 0 | grep olcRootPW: | awk '{ print $2}' | base64 -d | tee ${LOGFILE}
    echo | tee ${LOGFILE}
}

setup_log() {
    echo "****开启openldap日志访问功能" | tee ${LOGFILE}
    ldapsearch -Y external -H ldapi:/// -b cn=config "(objectClass=olcGlobal)" olcLogLevel -LLL
    cat<<EOF |tee ${LOGFILE}| ldapmodify -Q -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats
EOF

    cat<<'EOF' |tee ${LOGFILE} >/etc/rsyslog.d/10-slapd.conf
$template slapdtmpl,"[%$DAY%-%$MONTH%-%$YEAR% %timegenerated:12:19:date-rfc3339%] %app-name% %syslogseverity-text% %msg%\n"
local4.* /var/log/slapd.log;slapdtmpl
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

ldap_user_group() {
    local user=${1}
    local group=${2}
    local olcSuffix=${3}
    local action="${4:-add}"
    echo "****ADD USER GROUP ${user} -> ${group}" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapmodify -Q -Y EXTERNAL -H ldapi:///
dn:cn=${group},ou=groups,${olcSuffix}
changetype: modify
${action}: memberUid
memberUid: ${user}
EOF
    echo "****Search ${user} groups" | tee ${LOGFILE}
    ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:///  -b "${olcSuffix}" "(&(objectClass=posixGroup)(memberUid=${user}))"
}

add_group() {
    local group=${1}
    local gid=${2}
    local olcSuffix=${3}
    echo "****CREATE GROUP ${user}" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapadd -Q -Y EXTERNAL -H ldapi:///
dn: cn=${group},ou=groups,${olcSuffix}
objectClass: posixGroup
cn: ${group}
gidNumber: ${gid}
EOF
}
add_user() {
    local user=${1}
    local uid=${2}
    local olcSuffix=${3}
    # create new user
    # slapcat -n 0 | grep "olcObjectClasses:.*posixAccount"
    echo "****CREATE USER ${user}:${DEFAULT_ADD_USER_PASSWORD}" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapadd -Q -Y EXTERNAL -H ldapi:///
dn: uid=${user},ou=people,${olcSuffix}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: ${user}
sn: 部门
uid: ${user}
uidNumber: ${uid}
gidNumber: ${MAIL_GID}
homeDirectory: /home/${user}
userPassword: $(slappasswd -n -s ${DEFAULT_ADD_USER_PASSWORD})
shadowMax: 60
shadowMin: 1
shadowWarning: 7
shadowInactive: 7
shadowLastChange: $(echo $(date "+%s")/60/60/24 | bc)
EOF
    # ldapsearch -x cn=${user} -b ${olcSuffix}
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
    chown openldap:openldap "${ca}" "${cert}" "${key}"
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
    systemctl restart slapd
}

add_mdb_readonly_sysuser() {
    local olcSuffix=${1}
    local user=${2}
    local passwd=${3}
    echo "****Add ${user} for readonly querying the directory server" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapadd -Q -Y EXTERNAL -H ldapi:///
dn: cn=${user},ou=people,${olcSuffix}
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: readonly
userPassword: $(slappasswd -n -s ${passwd})
description: Bind DN user for LDAP Operations
EOF
    #  verify the Bind DN ACL with the following command
    ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config '(olcDatabase={1}mdb)' olcAccess
}

update_mdb_acl() {
    local olcSuffix=${1}
    echo "****Update database ACL" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapadd -Q -Y EXTERNAL -H ldapi:///
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: to attrs=userPassword,shadowLastChange,shadowExpire
  by self write
  by anonymous auth
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by dn.exact="cn=readonly,ou=people,${olcSuffix}" read
  by * none
olcAccess: to dn.exact="cn=readonly,ou=people,${olcSuffix}"
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none
olcAccess: to dn.subtree="${olcSuffix}"
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by users read
  by * none
EOF
}

init_user_organization_unit() {
    local olcRootDN=${1}
    local olcSuffix=${2}
    echo "****setup user organization unit" | tee ${LOGFILE}
    cat <<EOF |tee ${LOGFILE}| ldapadd -Q -Y EXTERNAL -H ldapi:///
dn: ou=people,${olcSuffix}
objectClass: organizationalUnit
objectClass: top
ou: people

dn: ou=groups,${olcSuffix}
objectClass: organizationalUnit
objectClass: top
ou: groups
EOF
    return 0
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
           DEFAULT_ADD_USER_PASSWORD=${DEFAULT_ADD_USER_PASSWORD}
          init:         -D sample.org -O "a b c" -P password
          addtls:       --ca ca.pem --cert /a.pem --key /a.key
          multimaster:  --srvid 104 --peer ldap://ip:389/>
          create ou:    --create_userou
          add ro usser: --rsysuser oureader --rsyspass pass
          add user:     -u user1 -u user2
          ALL IN ONE:   ..............
        -D|--domain  *    <str>  domain, sample.org
        -O|--org     *    <str>  organization, "my company. ltd."
        -P|--passwd  *  * <str>  slapd manager password
        --create_userou          create organization unit
        --rsysuser *      <str>  create readonly user for access ldap server 
        --rsyspass *      <str>
        -u|--uid          <str>  adduser mode uid in ldap, multi parameters
                                   default password: ${DEFAULT_ADD_USER_PASSWORD}
        --ca    *         <str>  ca file
        --cert  *         <str>  cert file
        --key   *         <str>  key file
        --srvid         * <num>  multimaster mode uniq id on each server, 101
        --peer          * <str>  multimaster mode other node url, ldap://ip:389/
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
    local passwd="" domain="" org="" ca="" cert="" key="" srvid="" peer="" create_userou="" rsysuser="" rsyspass=""
    local uid=()
    local opt_short="P:D:O:u:"
    local opt_long="passwd:,domain:,org:,ca:,cert:,key:,srvid:,peer:,uid:,create_userou,rsyspass:,rsysuser:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -P | --passwd)  shift; passwd=${1}; shift;;
            -D | --domain)  shift; domain=${1}; shift;;
            -O | --org)     shift; org=${1}; shift;;
            --create_userou)shift; create_userou=1;;
            --rsysuser)     shift; rsysuser=${1}; shift;;
            --rsyspass)     shift; rsyspass=${1}; shift;;
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
    [ -z "${passwd}" ] || [ -z "${domain}" ] || [ -z "${org}" ] || {
        init_ldap "${passwd}" "${domain}" "${org}"
        setup_log
        olcRootDN=$(slapcat -n 0 | grep -E -e "olcRootDN" | grep -v "cn=config" | awk '{print $2}')
        olcSuffix=$(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}')
        update_mdb_acl "${olcSuffix}"
        echo "****INIT OK ${TIMESPAN}" | tee ${LOGFILE}
    }
    [ -z "${create_userou}" ] || {
        olcRootDN=$(slapcat -n 0 | grep -E -e "olcRootDN" | grep -v "cn=config" | awk '{print $2}')
        olcSuffix=$(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}')
        init_user_organization_unit "${olcRootDN}" "${olcSuffix}"
        echo "****ADD DEFAULT MAIL GROUP" | tee ${LOGFILE}
        add_group "mail" ${MAIL_GID} "${olcSuffix}"
        echo "****INIT USER ORGANIZATION UNIT OK ${TIMESPAN}" | tee ${LOGFILE}
    }
    [ -z "${rsysuser}" ] || [ -z "${rsyspass}" ] || {
        olcSuffix=$(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}')
        add_mdb_readonly_sysuser "${olcSuffix}" "${rsysuser}" "${rsyspass}"
        echo "****CHANGE $_u passwd: ldappasswd -H ldap://127.0.0.1 -x -D cn=${rsysuser},ou=People,${olcSuffix} -w ${rsyspass}-a ${rsyspass} -S" | tee ${LOGFILE}
        echo "****ADD READONLY SYS USER OK ${TIMESPAN}" | tee ${LOGFILE}
    }
    [ -z "${ca}" ] || [ -z "${cert}" ] || [ -z "${key}" ] || {
        setup_starttls "${ca}" "${cert}" "${key}"
        echo "****check: LDAPTLS_REQCERT=never ldapsearch -x -b $(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}') -ZZ" | tee ${LOGFILE}
        echo "****INIT STARTTLS OK ${TIMESPAN}" | tee ${LOGFILE}
    }
    [ -z "${srvid}" ] || [ -z "${peer}" ] || [ -z "${passwd}" ] || {
        olcRootDN=$(slapcat -n 0 | grep -E -e "olcRootDN" | grep -v "cn=config" | awk '{print $2}')
        olcSuffix=$(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}')
        setup_multi_master_replication "${srvid}" "${peer}" "${olcRootDN}" "${olcSuffix}" "${passwd}"
        echo "****INIT MULTI MASTER OK ${TIMESPAN}" | tee ${LOGFILE}
    }
    ((${#uid[@]} == 0)) || {
        olcRootDN=$(slapcat -n 0 2>/dev/null | grep -E -e "olcRootDN" | grep -v "cn=config" | awk '{print $2}')
        olcSuffix=$(slapcat -n 0 2>/dev/null | grep "olcSuffix" | awk '{print $2}')
        for _u in "${uid[@]}"; do
            echo "****add uid <$_u: ${DEFAULT_ADD_USER_PASSWORD}>";
            add_user "$_u" 10000 "${olcSuffix}" || echo "****ADD $_u failed" | tee ${LOGFILE}
            ldap_user_group "$_u" ${MAIL_GID} "${olcSuffix}" "add"
            echo "****CHANGE $_u passwd: ldappasswd -H ldap://127.0.0.1 -x -D uid=$_u,ou=People,${olcSuffix} -w ${DEFAULT_ADD_USER_PASSWORD} -a ${DEFAULT_ADD_USER_PASSWORD} -S" | tee ${LOGFILE}
        done
        echo "****ADD USER ALL OK" | tee ${LOGFILE}
        return 0
    }
    return 0
}
main "$@"
