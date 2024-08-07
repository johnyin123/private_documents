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
VERSION+=("759b5d4[2022-09-29T08:44:33+08:00]:init_ldap.sh")
################################################################################
DEFAULT_ADD_USER_PASSWORD=${DEFAULT_ADD_USER_PASSWORD:-"password"}
TLS_CIPHER=${TLS_CIPHER:-SECURE256:-VERS-TLS-ALL:+VERS-TLS1.3:+VERS-TLS1.2:+VERS-DTLS1.2:+SIGN-RSA-SHA256:%SAFE_RENEGOTIATION:%STATELESS_COMPRESSION:%LATEST_RECORD_VERSION}
LOGFILE=""
MAIL_GROUP="mail"
MAIL_GID=9999
READONLY_SYSUSER_UNIT="rsysuer"

log() {
    echo "######$*" | tee ${LOGFILE} >&2
}

ldap_search() {
    log "ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// ${*}"
    ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// ${*} | tee ${LOGFILE}
}

ldap_modify() {
    log "ldapmodify -Q -Y EXTERNAL -H ldapi:/// ${*}"
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// ${*} | tee ${LOGFILE}
}

change_ldap_mgr_passwd() {
    passwd=${1}
    PASS_HASH=$(slappasswd -n -s ${passwd})
    cat <<EOF |tee ${LOGFILE}| ldapmodify -d 256 -H ldapi:// -Q -Y EXTERNAL
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: ${PASS_HASH}
EOF
    log "${PASS_HASH} => $(slapcat -n 0 | grep olcRootPW: | awk '{ print $2}' | base64 -d)"
}

setup_log() {
    log "SETUP SLAPD LOG"
    ldap_search -b cn=config "(objectClass=olcGlobal)" olcLogLevel
    cat<<EOF |tee ${LOGFILE}| ldap_modify
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
    log "openldap dpkg-reconfigure"
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
    log "ADD USER GROUP ${user} -> ${group}"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn:cn=${group},ou=group,${olcSuffix}
changetype: modify
${action}: memberUid
memberUid: ${user}
EOF
#    log "Search ${user} group"
#    ldap_search -b "${olcSuffix}" "(&(objectClass=posixgroup)(memberUid=${user}))"
}

add_group() {
    local group=${1}
    local gid=${2}
    local olcSuffix=${3}
    log "CREATE GROUP ${group}"
    ldap_search -b "${olcSuffix}" "(&(objectClass=posixgroup)(cn=${group}))" | grep -q "dn\s*:" && {
        log "NO ADD, GROUP ${group} EXIST!!!"
        return 1
    }
    ldap_search -b "${olcSuffix}" "(&(objectClass=posixgroup)(gidNumber=${gid}))" | grep -q "dn\s*:" && {
        log "NO ADD, GROUPID ${gid} EXIST!!!"
        return 2
    }
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: cn=${group},ou=group,${olcSuffix}
changetype: add
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
    log "CREATE USER ${user}:${DEFAULT_ADD_USER_PASSWORD}"
    ldap_search -b "${olcSuffix}" "(&(objectClass=posixaccount)(uid=${user}))" | grep -q "dn\s*:" && {
        log "NO ADD, USER ${user} EXIST!!!"
        return 1
    }
    ldap_search -b "${olcSuffix}" "(&(objectClass=posixaccount)(uidNumber=${uid}))" | grep -q "dn\s*:" && {
        log "NO ADD, USERID ${uid} EXIST!!!"
        return 2
    }
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: uid=${user},ou=people,${olcSuffix}
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: ${user}
sn: 测试用户
telephoneNumber: N/A
physicalDeliveryOfficeName: 部门
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
    ldap_search -b "${olcSuffix}" "(&(objectClass=posixaccount)(uid=${user}))" | grep -q "dn\s*:"
}

setup_multi_master_replication() {
    local srvid=${1} # specify uniq olcServerID number on each server, 101
    local peer=${2} # specify another LDAP server's URI, ldap://10.0.0.51:389/
    local olcRootDN=${3}
    local olcSuffix=${4}
    local passwd=${5}
    log "SETUP MULTI_MASTER REPLICATION.1"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: cn=module,cn=config
changetype: add
objectClass: olcModuleList
cn: module
olcModulePath: /usr/lib/ldap
olcModuleLoad: syncprov.la
EOF
    log "SETUP MULTI_MASTER REPLICATION.2"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpSessionLog: 100
EOF
    # [retry interval] [retry times] [interval of re-retry] [re-retry times]
    # retry="30 5 300 3"
    log "SETUP MULTI_MASTER REPLICATION.3"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
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
    log "SETUP START_TLS"
    log "TLSVerifyClient { never | allow | try | demand }"
    # never by default,
    # allow the server will ask for a client certificate
    # demand the certificate is requested and a valid certificate must be provided
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: cn=config
changetype: modify
$(
[ -z "${ca}" ] || {
cat <<EO_CA
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: ${ca}
-
# replace: olcTLSVerifyClient
# olcTLSVerifyClient: demand
#-
EO_CA
})
replace: olcTLSCertificateFile
olcTLSCertificateFile: ${cert}
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: ${key}
-
replace: olcTLSProtocolMin
olcTLSProtocolMin: 3.3
-
replace: olcTLSCipherSuite
olcTLSCipherSuite: ${TLS_CIPHER}
-
replace: olcDisallows
olcDisallows: bind_anon tls_2_anon
EOF
    log "Modify openldap startup parameters: add ldaps:///"
    sed -i "s|^SLAPD_SERVICES=.*|SLAPD_SERVICES=\"ldap:/// ldapi:/// ldaps:///\"|g" /etc/default/slapd
    log "Restart slapd service"
    systemctl restart slapd
    log "Check slapd TLS, PORT:0.0.0.0:636"
    timeout 0.1 openssl s_client -connect 127.0.0.1:636 -showcerts < /dev/null || true
    openssl s_client -host 127.0.0.1 -port 389 -starttls ldap < /dev/null ||  true
}

add_mdb_readonly_sysuser() {
    local olcSuffix=${1}
    local user=${2}
    local passwd=${3}
    log "Add [cn=${user},ou=${READONLY_SYSUSER_UNIT},${olcSuffix}] for read_only querying the directory server"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: cn=${user},ou=${READONLY_SYSUSER_UNIT},${olcSuffix}
changetype: add
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: ${user}
userPassword: $(slappasswd -n -s ${passwd})
description: Bind DN user
EOF
    # verify the Bind DN ACL with the following command
    ldap_search -b cn=config '(olcDatabase={1}mdb)' olcAccess
}

update_mdb_acl() {
    local olcSuffix=${1}
    log "Update database ACL"
    # olcAccess: to dn.subtree="${olcSuffix}"
    #   by group(s)/groupOfNames/member="cn=manager,ou=group,${olcSuffix}" manage
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: to attrs=userPassword,shadowLastChange,shadowExpire
  by self write
  by anonymous auth
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by dn.subtree="ou=${READONLY_SYSUSER_UNIT},${olcSuffix}" read
  by * none
olcAccess: to dn.subtree="ou=${READONLY_SYSUSER_UNIT},${olcSuffix}"
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none
olcAccess: to dn.subtree="${olcSuffix}"
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by users read
  by * none
EOF
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: ou=${READONLY_SYSUSER_UNIT},${olcSuffix}
changetype: add
objectClass: organizationalUnit
objectClass: top
ou: ${READONLY_SYSUSER_UNIT}
description: Bind DN for LDAP Operations
EOF

}

init_uidnumber_autoincrease() {
    local olcSuffix=${1}
    log "setup posixAccount(uidNumber) increaser"
    log "add schema, new objectclass"
    cat <<'EOF' |tee ${LOGFILE}| ldap_modify
dn: cn=schema,cn=config
changetype: modify
add: olcObjectClasses
olcObjectClasses: ( 1.3.6.1.4.1.19173.2.2.2.8
  NAME 'uidNext'
  SUP top STRUCTURAL
  DESC 'Where we get the next uidNumber from'
  MUST ( cn $ uidNumber ) )
EOF
    log "add uidNext object"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: cn=uidNext,${olcSuffix}
changetype: add
objectClass: uidNext
uidNumber: 9999
EOF
    inc_max_free_uidnumber "${olcSuffix}"
}

inc_max_free_uidnumber() {
    local olcSuffix=${1}
    log "Increase 1 uidNext"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: cn=uidNext,${olcSuffix}
changetype: modify
increment: uidNumber
uidNumber: 1
EOF
}

get_max_free_uidnumber() {
    local olcSuffix=${1}
    ldap_search -b cn=uidNext,${olcSuffix} uidNumber | grep -i uidNumber | cut -d':' -f2
}

init_user_organization_unit() {
    local olcSuffix=${1}
    log "setup user organization unit"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: ou=people,${olcSuffix}
changetype: add
objectClass: organizationalUnit
objectClass: top
ou: people

dn: ou=group,${olcSuffix}
changetype: add
objectClass: organizationalUnit
objectClass: top
ou: group
EOF
    init_uidnumber_autoincrease "${olcSuffix}"
    return 0
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
           DEFAULT_ADD_USER_PASSWORD=${DEFAULT_ADD_USER_PASSWORD}
          init:         -D sample.org -O "a b c" -P password
          addtls:       <--ca ca.pem> --cert /a.pem --key /a.key
          multimaster:  --srvid 104 --peer ldap://ip:389/>
          create ou:    --create_userou
          add ro user(read_only) : --rsysuser user --rsyspass pass
          add user:     -u user1 -u user2
          ALL IN ONE:   ..............
        -D|--domain  *    <str>  domain, sample.org
        -O|--org     *    <str>  organization, "my company. ltd."
        -P|--passwd  *  * <str>  slapd manager password
        --create_userou          create organization unit
        --rsysuser *      <str>  read_only accessuser name
        --rsyspass *      <str>  read_only accessuser pass
        -u|--user         <str>  add mail user, group(${MAIL_GROUP}:${MAIL_GID}), multi parameters
                                   default password: ${DEFAULT_ADD_USER_PASSWORD}
        -g|--group)       <str>  add new group, multi parameters
        --ca              <str>  ca file, if cafile not null TLSVerifyClient
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
          # ldapsearch chinese word encode base64
        # delete user&group
        ldapdelete -x -W -D "cn=admin,dc=example,dc=org" "uid=testuser1,ou=People,dc=example,dc=com"
        ldapdelete -x -W -D "cn=admin,dc=example,dc=org" "cn=testuser1,ou=Group,dc=example,dc=com"
EOF
    exit 1
}
main() {
    local _u="" _max_id="" olcRootDN="" olcSuffix=""
    local passwd="" domain="" org="" ca="" cert="" key="" srvid="" peer="" create_userou="" rsysuser="" rsyspass=""
    local users=()
    local group=()
    local opt_short="P:D:O:u:g:"
    local opt_long="passwd:,domain:,org:,ca:,cert:,key:,srvid:,peer:,user:,group:,create_userou,rsysuser:,rsyspass:,"
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
            -u | --user)    shift; users+=(${1}); shift;;
            -g | --group)   shift; group+=(${1}); shift;;
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
        olcSuffix=$(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}')
        update_mdb_acl "${olcSuffix}"
        log "INIT OK"
    }
    [ -z "${create_userou}" ] || {
        olcSuffix=$(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}')
        init_user_organization_unit "${olcSuffix}"
        log "ADD DEFAULT MAIL GROUP"
        add_group "${MAIL_GROUP}" ${MAIL_GID} "${olcSuffix}"
        log "INIT USER ORGANIZATION UNIT OK"
    }
    [ -z "${rsysuser}" ] || [ -z "${rsyspass}" ] || {
        olcSuffix=$(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}')
        add_mdb_readonly_sysuser "${olcSuffix}" "${rsysuser}" "${rsyspass}"
        log "**************************************************"
        log "search_base = ou=people,${olcSuffix}"
        log "bind_dn     = cn=${rsysuser},ou=${READONLY_SYSUSER_UNIT},${olcSuffix}"
        log "bind_pw     = ${rsyspass}"
        log "**************************************************"
        log "CHANGE $_u passwd: ldappasswd -H ldap://127.0.0.1 -x -D cn=${rsysuser},ou=${READONLY_SYSUSER_UNIT},${olcSuffix} -w ${rsyspass}-a ${rsyspass} -S"
        log "ADD READONLY SYS USER OK"
    }
    [ -z "${cert}" ] || [ -z "${key}" ] || {
        setup_starttls "${ca}" "${cert}" "${key}"
        log "check: LDAPTLS_REQCERT=never ldapsearch -x -b $(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}') -ZZ"
        log "cat /etc/ldap/ldap.conf"
        log "LDAPTLS_CACERT=/ca.pem TLS_CERT TLS_KEY TLS_REQCERT ldapsearch"
        log "INIT STARTTLS OK"
    }
    [ -z "${srvid}" ] || [ -z "${peer}" ] || [ -z "${passwd}" ] || {
        olcRootDN=$(slapcat -n 0 | grep -E -e "olcRootDN" | grep -v "cn=config" | awk '{print $2}')
        olcSuffix=$(slapcat -n 0 | grep "olcSuffix" | awk '{print $2}')
        setup_multi_master_replication "${srvid}" "${peer}" "${olcRootDN}" "${olcSuffix}" "${passwd}"
        log "INIT MULTI MASTER OK"
    }
    ((${#group[@]} == 0)) || {
        olcSuffix=$(slapcat -n 0 2>/dev/null | grep "olcSuffix" | awk '{print $2}')
        _max_id=$(ldap_search -b "${olcSuffix}" "(objectclass=posixgroup)" gidnumber | grep -e '^gid' | cut -d':' -f2 | sort | tail -1)
        _max_id=${_max_id:-MAIL_GID}
        for _u in "${group[@]}"; do
            let _max_id=_max_id+1
            log "add group <$_u: ${_max_id}>"
            add_group "$_u" "${_max_id}" "${olcSuffix}" || log "ADD GROUP($?) $_u ERROR, continue"
        done
        log "ADD GROUP ALL OK"
    }
    ((${#users[@]} == 0)) || {
        olcSuffix=$(slapcat -n 0 2>/dev/null | grep "olcSuffix" | awk '{print $2}')
        for _u in "${users[@]}"; do
            _max_id=$(get_max_free_uidnumber "${olcSuffix}")
            log "add user <$_u: ${DEFAULT_ADD_USER_PASSWORD}>"
            add_user "$_u" ${_max_id} "${olcSuffix}" && ldap_user_group "$_u" ${MAIL_GROUP} "${olcSuffix}" "add" || log "add_user($?) $_u:${MAIL_GROUP} error, continue"
            inc_max_free_uidnumber "${olcSuffix}"
            log "CHECK:ldapwhoami -v -h 127.0.0.1 -D uid=$_u,ou=people,${olcSuffix} -x -w ${DEFAULT_ADD_USER_PASSWORD}"
            log "CHANGE $_u passwd: ldappasswd -H ldap://127.0.0.1 -x -D uid=$_u,ou=People,${olcSuffix} -w ${DEFAULT_ADD_USER_PASSWORD} -a ${DEFAULT_ADD_USER_PASSWORD} -S"
        done
        log "ADD USER ALL OK"
    }
    log "ALL DONE"
    return 0
}
main "$@"
