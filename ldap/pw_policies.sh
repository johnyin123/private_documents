#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2022-09-21T17:25:37+08:00]:pw_policies.sh")
################################################################################
LOGFILE=${LOGFILE:-}
# failed lock user for 300 seconds
LOCK=${LOCK:-300}
# 5 times failed lock use
TIMES=${TIMES:-5}

log() {
    echo "######$*" | tee ${LOGFILE} >&2
}

ldap_modify() {
    log "ldapmodify -Q -Y EXTERNAL -H ldapi:/// ${*}"
    ldapmodify -Q -Y EXTERNAL -H ldapi:/// ${*} | tee ${LOGFILE}
}

main() {
    [ -z ${LOGFILE} ] || LOGFILE="-a ${LOGFILE}"
    olcSuffix=$(slapcat -n 0 2>/dev/null | grep "olcSuffix" | awk '{print $2}')
    log "Load Password Policy Module"
    slapcat -n 0 | grep -i -E "olcModuleLoad|olcModulePath"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: ppolicy.la
EOF
    log "add ppolicy schema"
    ldapadd -Y EXTERNAL -H ldapi:/// -f  /etc/ldap/schema/ppolicy.ldif

    log "Create Password Policies OU Container"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: ou=pwpolicy,${olcSuffix}
changetype: add
objectClass: organizationalUnit
objectClass: top
ou: pwpolicy
EOF
    log "Create OpenLDAP Password Policy Overlay DN"
    log "man slapo-ppolicy for detail!!!"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: olcOverlay=ppolicy,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: ppolicy
olcPPolicyDefault: cn=default,ou=pwpolicy,${olcSuffix}
olcPPolicyHashCleartext: TRUE
EOF
    log "Create OpenLDAP Password Policies(pwdLockoutDuration, lock seconds)"
    cat <<EOF |tee ${LOGFILE}| ldap_modify
dn: cn=default,ou=pwpolicy,${olcSuffix}
changetype: add
objectClass: Person
objectClass: pwdPolicyChecker
objectClass: pwdPolicy
cn: pwpolicy
sn: pwpolicy
pwdAttribute: userPassword
pwdLockout: TRUE
pwdLockoutDuration: ${LOCK}
pwdMaxFailure: ${TIMES}
pwdFailureCountInterval: 0
EOF
    log "Testing Password Policies"
    log "ldapwhoami -v -h 127.0.0.1 -D uid=user1,ou=people,${olcSuffix} -x -w password"
    log "Unlock user removing the operational attribute pwdAccountLockedTime"
    cat<<EOF |tee ${LOGFILE}
dn: uid=user1,ou=people,${olcSuffix}
changetype: modify
delete: pwdAccountLockedTime
EOF
    return 0
}

main "$@"
