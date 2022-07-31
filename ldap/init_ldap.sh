#!/usr/bin/env bash
yum install openldap-servers openldap-clients openldap-servers-sql compat-openldap migrationtools

PASSWORD=123456
ADMIN_USR=root
DOMAIN=testlab
echo "olcRootPW: $(slappasswd -s ${PASSWORD})" >> /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{2\}hdb.ldif
sed -i "s/cn=Manager/cn=${ADMIN_USR}/g" /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{2\}hdb.ldif
sed -i "s/dc=my-domain/dc=${DOMAIN}/g"  /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{2\}hdb.ldif

sed -i "s/cn=Manager/cn=${ADMIN_USR}/g" /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{1\}monitor.ldif
sed -i "s/dc=my-domain/dc=${DOMAIN}/g"  /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{1\}monitor.ldif

slaptest -u


systemctl enable slapd
systemctl start slapd
systemctl status slapd

cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap -R /var/lib/ldap
chmod 700 -R /var/lib/ldap
ls -l /var/lib/ldap/

ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

echo "修改生成ldif文件的脚本"
cat /usr/share/migrationtools/migrate_common.ph | egrep 'DEFAULT_MAIL_DOMAIN|DEFAULT_BASE|EXTENDED_SCHEMA' | head -3
# $DEFAULT_MAIL_DOMAIN = "padl.com";
# $DEFAULT_BASE = "dc=padl,dc=com";
# $EXTENDED_SCHEMA = 0;

sed -i "s/DEFAULT_MAIL_DOMAIN *=.*/DEFAULT_MAIL_DOMAIN = \"${DOMAIN}.com\";/g" /usr/share/migrationtools/migrate_common.ph
sed -i "s/DEFAULT_BASE *=.*/DEFAULT_BASE = \"dc=${DOMAIN},dc=com\";/g" /usr/share/migrationtools/migrate_common.ph
sed -i "s/EXTENDED_SCHEMA *=.*/EXTENDED_SCHEMA = 1;" /usr/share/migrationtools/migrate_common.ph

echo "添加系统用户及用户组用于后期导入openldap"
groupadd ldapgroup1
groupadd ldapgroup2
useradd -g ldapgroup1 ldapuser1
useradd -g ldapgroup2 ldapuser2
echo "123456" | passwd --stdin ldapuser1
echo "123456" | passwd --stdin ldapuser2
grep ":10[0-9][0-9]" /etc/passwd | grep ldap > /root/users
grep ":10[0-9][0-9]" /etc/group | grep ldap > /root/groups
/usr/share/migrationtools/migrate_passwd.pl /root/users > /root/users.ldif
/usr/share/migrationtools/migrate_group.pl /root/groups > /root/groups.ldif
cat /root/groups.ldif
cat /root/users.ldif

echo "配置openldap基础的数据库"
cat >/root/base.ldif<<EOF
dn: dc=${DOMAIN},dc=com
o: ${DOMAIN} com
dc: ${DOMAIN}
objectClass: top
objectClass: dcObject
objectclass: organization

dn: cn=${ADMIN_USR},dc=${DOMAIN},dc=com
cn: ${ADMIN_USR}
objectClass: organizationalRole
description: Directory Manager

dn: ou=People,dc=${DOMAIN},dc=com
ou: People
objectClass: top
objectClass: organizationalUnit

dn: ou=Group,dc=${DOMAIN},dc=com
ou: Group
objectClass: top
objectClass: organizationalUnit
EOF
ldapadd -x -w "${PASSWORD}" -D "cn=${ADMIN_USR},dc=${DOMAIN},dc=com" -f /root/base.ldif

echo "导入用户和组信息数据到Openldap"
ldapadd -x -w "${PASSWORD}" -D "cn=${ADMIN_USR},dc=${DOMAIN},dc=com" -f /root/users.ldif
ldapadd -x -w "${PASSWORD}" -D "cn=${ADMIN_USR},dc=${DOMAIN},dc=com" -f /root/groups.ldif

ls -l /var/lib/ldap
ldapsearch -x -b "dc=${DOMAIN},dc=com" -H "ldap://127.0.0.1"
ldapsearch -LLL -x -D "cn=${ADMIN_USR},dc=${DOMAIN},dc=com" -w "${PASSWORD}" -b "dc=${DOMAIN},dc=com" "uid=ldapuser1"
ldapsearch -LLL -x -D "cn=${ADMIN_USR},dc=${DOMAIN},dc=com" -w "${PASSWORD}" -b "dc=${DOMAIN},dc=com" "uid=ldapgroup1"

#######################

echo "开启openldap日志访问功能"
cat>/root/loglevel.ldif<<EOF
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats
EOF

cat>>/etc/rsyslog.conf<<EOF
local4 .* /var/log/slapd.log
EOF
systemctl restart rsyslog
systemctl restart slapd
tail -10 /var/log/slapd.log

echo "关联openldap中的用户和组关系"
cat > add_user_to_groups.ldif <<EOF
dn: cn=ldapgroup1,ou=Group,dc=${DOMAIN},dc=com
changetype: modify
add: memberuid
memberuid: ldapuser1
EOF
ldapadd -x -w "${PASSWORD}" -D "cn=${ADMIN_USR},dc=${DOMAIN},dc=com" -f /root/add_user_to_groups.ldif

echo "查询openldap信息"

ldapsearch -LLL -x -D 'cn=root,dc=testlab,dc=com' -w "123456" -H ldap://0.0.0.0:389/ -b 'dc=testlab,dc=com'
