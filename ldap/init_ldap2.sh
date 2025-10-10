export LDAP_DOMAIN="sample.org"
export LDAP_PASSWORD="password"
# # # # # # # # # # # # # # # # # # # # 
export LDAP_CFG_DIR="/etc/ldap/slapd.d"
export LDAP_RUN_DIR="/var/run/slapd"
export LDAP_BACKEND_DIR="/var/lib/ldap"
export LDAP_MOD_DIR="/usr/lib/ldap"
export LDAP_SCHEMA_DIR="/etc/ldap/schema"
# # # # # # # # # # # # # # # # # # # # 
export LDAP_PASSWORD_SSHA=$(slappasswd -u -h '{SSHA}' -s ${LDAP_PASSWORD})
export LDAP_SUFFIX="dc=$(echo ${LDAP_DOMAIN} | sed 's/^\.//; s/\./,dc=/g')"

[ -d ${LDAP_CFG_DIR}/cn=config ] && { exit 0; }
pkill -9 slapd
rm -fvr ${LDAP_CFG_DIR}/* ${LDAP_RUN_DIR}/* ${LDAP_BACKEND_DIR}/*
install -v -d -m 0755 --group=openldap --owner=openldap ${LDAP_CFG_DIR}
install -v -d -m 0755 --group=openldap --owner=openldap ${LDAP_RUN_DIR}

cat<<EO_LDIF | tee conf.ldif | su openldap -s /bin/bash -c "slapadd -n0 -F ${LDAP_CFG_DIR}"
dn: cn=config
objectClass: olcGlobal
cn: config
olcConfigDir: ${LDAP_CFG_DIR}
olcArgsFile: ${LDAP_RUN_DIR}/slapd.args
olcPidFile: ${LDAP_RUN_DIR}/slapd.pid
olcToolThreads: 1
olcLogLevel: stats

dn: cn=module{0},cn=config
objectClass: olcModuleList
cn: module{0}
olcModulePath: ${LDAP_MOD_DIR}
olcModuleLoad: {0}back_mdb

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

include: file://${LDAP_SCHEMA_DIR}/core.ldif
include: file://${LDAP_SCHEMA_DIR}/cosine.ldif
include: file://${LDAP_SCHEMA_DIR}/nis.ldif
include: file://${LDAP_SCHEMA_DIR}/inetorgperson.ldif

dn: olcDatabase={-1}frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: {-1}frontend
olcSizeLimit: 1000
olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
olcAccess: {1}to dn.exact="" by * read
olcAccess: {2}to dn.base="cn=Subschema" by * read

dn: olcDatabase={0}config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: {0}config
olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
olcRootDN: cn=admin,cn=config

dn: olcDatabase={1}mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {1}mdb
olcDbDirectory: ${LDAP_BACKEND_DIR}
olcSuffix: ${LDAP_SUFFIX}
olcLastMod: TRUE
olcRootDN: cn=admin,${LDAP_SUFFIX}
olcRootPW: ${LDAP_PASSWORD_SSHA}
olcDbCheckpoint: 512 30
olcDbIndex: objectClass eq
olcDbIndex: cn,uid eq
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: member,memberUid eq
olcDbMaxSize: 1073741824
olcAccess: {0}to attrs=userPassword,shadowLastChange,shadowExpire
    by self write
    by anonymous auth
    by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
    by dn.subtree="ou=rsysuer,${LDAP_SUFFIX}" read
    by * none
olcAccess: {1}to dn.subtree="ou=rsysuer,${LDAP_SUFFIX}"
    by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
    by * none
olcAccess: {2}to dn.subtree="${LDAP_SUFFIX}"
    by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
    by users read
    by * none
EO_LDIF
cat<<EO_LDIF | tee data.ldif | su openldap -s /bin/bash -c "slapadd -n1 -F ${LDAP_CFG_DIR}"
dn: ${LDAP_SUFFIX}
# objectClass: domain
objectClass: top
objectClass: dcObject
objectClass: organization
dc: $(echo ${LDAP_DOMAIN} | sed 's/^\.//; s/\..*$//')
o: ${LDAP_DOMAIN} company

dn: ou=people,${LDAP_SUFFIX}
objectClass: organizationalUnit
objectClass: top
ou: people

dn: ou=group,${LDAP_SUFFIX}
objectClass: organizationalUnit
objectClass: top
ou: group
EO_LDIF


echo "create test data ..............."

user=testuser
uid=100001
group=group_name
gid=100001

cat <<EO_LDIF | tee group | su openldap -s /bin/bash -c "slapadd -n1 -F ${LDAP_CFG_DIR}"
# ----------------------------------
dn: cn=${group},ou=group,${LDAP_SUFFIX}
objectClass: posixGroup
cn: ${group}
gidNumber: ${gid}

# ----------------------------------
dn: uid=${user},ou=people,${LDAP_SUFFIX}
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
gidNumber: ${gid}
homeDirectory: /home/${user}
userPassword: $(slappasswd -n -s password)
shadowMax: 60
shadowMin: 1
shadowWarning: 7
shadowInactive: 7
shadowLastChange: $(echo $(($(date "+%s")/60/60/24)))
EO_LDIF
cat <<EOF | tee test
# ----------------------------------
# #start slapd:
slapd -h 'ldapi:/// ldap:///' -u openldap -g openldap
# #search user:
ldapsearch -LLL -Y EXTERNAL -H ldapi:/// -b ${LDAP_SUFFIX} '(&(objectClass=posixaccount)(uid=${user}))'
# #search user, use admin:
ldapsearch -LLL -x -W -D "cn=admin,${LDAP_SUFFIX}" -b ${LDAP_SUFFIX} '(&(objectClass=posixaccount)(uid=${user}))'
# #search user, use self:
ldapsearch -LLL -x -W -D "uid=${user},ou=People,${LDAP_SUFFIX}" -b ${LDAP_SUFFIX} '(&(objectClass=posixaccount)(uid=${user}))'
# # delete user&group, use admin
ldapdelete -x -W -D "cn=admin,${LDAP_SUFFIX}" "uid=${user},ou=People,${LDAP_SUFFIX}"
ldapdelete -x -W -D "cn=admin,${LDAP_SUFFIX}" "cn=${group},ou=Group,${LDAP_SUFFIX}"
EOF
