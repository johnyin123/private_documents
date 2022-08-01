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
VERSION+=("8e20a78[2022-07-31T08:00:47+08:00]:init_ldap.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
PASSWORD=123456

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
    cat <<EOF >ldapuser.ldif
dn: uid=${user},ou=people,dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: ${user}
userPassword: $(slappasswd -n -s ${passwd})
dn: cn=${user},ou=groups,dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}}
objectClass: posixGroup
cn: ${user}
gidNumber: 2000
memberUid: bullseye
EOF
root@dlp:~# ldapadd -x -D cn=admin,dc=srv,dc=world -W -f ldapuser.ldif
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
}

setup_ssl() {
    local ca=${1}
    local cert=${2}
    local key=${3}
    cat <<EOF >mod_ssl.ldif
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
    ldapmodify -Y EXTERNAL -H ldapi:/// -f mod_ssl.ldif
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
        -e "s|^olcRootPW\s*:.*|olcRootPW:: $(slappasswd -n -s ${PASSWORD}| base64 -w0)|g" \
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
    ldapadd -x -D cn=admin,dc=${dc1}${dc2:+,dc=${dc2}}${dc3:+,dc=${dc3}} -w ${PASSWORD} -v -f base.ldif || true
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        --domain   *    <str>  domain name "sample.org"
        --lan      *    <str>  lan ipaddr, 192.168.1.2
        --wan      *    <str>  wan ipaddr.
        --log                  with named access log (/var/log/named/named.log), default no log 
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        # apt -y install slapd ldap-utils
        # dpkg-reconfigure slapd
        # test ssl
        ldapsearch -x -b dc=example,dc=org -ZZ
        # delete user&group
        ldapdelete -x -W -D 'cn=admin,dc=example,dc=org' "uid=testuser1,ou=People,dc=example,dc=com"
        ldapdelete -x -W -D 'cn=admin,dc=example,dc=org' "cn=testuser1,ou=Group,dc=example,dc=com"
EOF
    exit 1
}
main() {
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
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
    init_ldap "test" "mail"
    echo "ALL OK ${TIMESPAN}"
    return 0
}
main "$@"
