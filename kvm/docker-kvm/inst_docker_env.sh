#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
libvirtd_dir="${1:?${0} <libvirtd_dir> <simplekvm_dir>}"
simplekvm_dir="${2:?${0} <libvirtd_dir> <simplekvm_dir>}"

# only libvirtd access META_SRV
META_SRV=simplekvm.registry.local
meta_srv_addr=192.168.167.1

# only simplekvm access GOLD_SRV
GOLD_SRV=simplekvm.registry.local
gold_srv_ipaddr=192.168.167.1

# tanent access CTRL_PANEL_SRV, public access
CTRL_PANEL_SRV=user.registry.local

LDAP_SRV=ldap
LDAP_PORT=10389
LDAP_PASSWORD='Pass4LDAP@docker'

ETCD_SRV=etcd
ETCD_PORT=2379

target=${libvirtd_dir}
cat <<EOF
# ===================================================
# ===================================================
${target}/ca.pem
${target}/kvmsrvs.key
${target}/kvmsrvs.pem
${target}/vms-xml/
${target}/secrets/
${target}/storage/
# ===================================================
docker create --name libvirtd --restart always \\
    --hostname \${HOSTNAME:-\$(hostname)} \\
    --add-host \${HOSTNAME:-\$(hostname)}:127.0.0.1 \\
    --network host \\
    --privileged \\
    --device /dev/kvm \\
    --add-host ${META_SRV}:${meta_srv_addr} \\
    -v ${target}/ca.pem:/etc/libvirt/pki/ca-cert.pem \\
    -v ${target}/kvmsrvs.key:/etc/libvirt/pki/server-key.pem \\
    -v ${target}/kvmsrvs.pem:/etc/libvirt/pki/server-cert.pem \\
    -v ${target}/vms-xml:/etc/libvirt/qemu \\
    -v ${target}/secrets:/etc/libvirt/secrets \\
    -v ${target}/storage:/etc/libvirt/storage \\
    -v /storage:/storage \\
    registry.local/libvirtd/kvm:trixie

    # -v ${target}/run/libvirt:/var/run/libvirt \\
    # -v ${target}/log:/var/log/libvirt \\
    # -v ${target}/lib/libvirt:/var/lib/libvirt \\
EOF
cat <<EOF
# ===================================================
# ===================================================
docker create --name ${ETCD_SRV} --restart always \\
 --network br-int \\
 --env ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379    \\
 --env ETCD_ADVERTISE_CLIENT_URLS=http://0.0.0.0:2379 \\
 --env ETCD_LOG_LEVEL='warn'                          \\
 registry.local/libvirtd/etcd:trixie
EOF

cat <<EOF
# ===================================================
# ===================================================
docker create --name ${LDAP_SRV} --restart always \\
 --network br-int \\
 --env LDAP_DOMAIN="neusoft.internal" \\
 --env LDAP_PASSWORD=${LDAP_PASSWORD} \\
 registry.local/libvirtd/slapd:trixie
EOF


target=${simplekvm_dir}
cat <<EOF
# ===================================================
# ===================================================
${target}/config
${target}/id_rsa
${target}/id_rsa.pub
${target}/cacert.pem
${target}/clientkey.pem
${target}/clientcert.pem
# ===================================================
docker create --name simplekvm --restart always \\
 --network br-int --ip 192.168.169.123 \\
 --env LDAP_SRV_URL=ldap://${LDAP_SRV}:${LDAP_PORT} \\
 --env META_SRV=${META_SRV} \\
 --env CTRL_PANEL_SRV=${CTRL_PANEL_SRV} \\
 --env GOLD_SRV=${GOLD_SRV} --add-host ${GOLD_SRV}:${gold_srv_ipaddr} \\
 --env ETCD_PREFIX=/simple-kvm/work --env ETCD_SRV=${ETCD_SRV} --env ETCD_PORT=${ETCD_PORT} \\
 -v ${target}/config:/home/simplekvm/.ssh/config \\
 -v ${target}/id_rsa:/home/simplekvm/.ssh/id_rsa \\
 -v ${target}/id_rsa.pub:/home/simplekvm/.ssh/id_rsa.pub \\
 -v ${target}/cacert.pem:/etc/pki/CA/cacert.pem \\
 -v ${target}/clientkey.pem:/etc/pki/libvirt/private/clientkey.pem \\
 -v ${target}/clientcert.pem:/etc/pki/libvirt/clientcert.pem \\
 -v ${target}/clientkey.pem:/etc/nginx/ssl/simplekvm.key \\
 -v ${target}/clientcert.pem:/etc/nginx/ssl/simplekvm.pem \\
 registry.local/libvirtd/simplekvm:trixie
EOF

cat <<'EO_DOC'
# ===================================================
######## init ldap user
# ===================================================
ldap_srv=192.168.169.192
gid=simplekvm
uid=admin
cat <<EOF | ldapadd -x -w adminpass -D "cn=admin,dc=neusoft,dc=internal" -H ldap://${ldap_srv}:10389
dn: cn=${gid},ou=group,dc=neusoft,dc=internal
objectClass: posixGroup
cn: ${gid}
gidNumber: 100001

dn: uid=${uid},ou=people,dc=neusoft,dc=internal
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: ${uid}
sn: simplekvm用户${uid}
telephoneNumber: N/A
physicalDeliveryOfficeName: 部门
uid: ${uid}
uidNumber: 100001
gidNumber: 100001
homeDirectory: /home/${uid}
userPassword: dummy
shadowMax: 60
shadowMin: 1
shadowWarning: 7
shadowInactive: 7
shadowLastChange: $(echo $(($(date "+%s")/60/60/24)))
EOF
EO_DOC
cat <<EO_DOC
password=adminpass
echo "init  passwd" && ldappasswd -x -w \${password} -D "cn=admin,dc=neusoft,dc=internal" -H ldap://\${ldap_srv}:10389 -s "${LDAP_PASSWORD}" "uid=\${uid},ou=people,dc=neusoft,dc=internal"
echo "check passwd" && ldapwhoami -x -w \${password} -D "uid=\${uid},ou=people,dc=neusoft,dc=internal" -H ldap://\${ldap_srv}:10389
# echo "change passwd" && ldappasswd -x -w \${password} -D "uid=simplekvm,ou=people,dc=neusoft,dc=internal" -H ldap://\${ldap_srv}:10389 -s "newpass2" "uid=simplekvm,ou=people,dc=neusoft,dc=internal"
EO_DOC
