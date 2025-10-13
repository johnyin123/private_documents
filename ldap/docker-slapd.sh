#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
file_exists() { [ -e "$1" ]; }
ARCH=(amd64 arm64)

type=slapd
ver=trixie
nsname=simplekvm

for fn in make_docker_image.sh tpl_overlay.sh; do
    file_exists "${fn}" || { log "${fn} no found"; exit 1; }
done

export BUILD_NET=${BUILD_NET:-host}
export REGISTRY=registry.local
export IMAGE=debian:trixie       # # BASE IMAGE
export NAMESPACE=

for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    cat <<EODOC > ${type}-${arch}/docker/build.run
set -o nounset -o pipefail -o errexit
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
APT="apt -y ${PROXY:+--option Acquire::http::Proxy=\"${PROXY}\" }--no-install-recommends"
\${APT} update
\${APT} install slapd
rm /etc/ldap/slapd.d/* /var/lib/ldap/* -fr
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d ! -iname 'zh_CN*' ! -iname 'en*' | xargs -I@ rm -rf @ || true
rm -rf /var/lib/apt/* /var/cache/* /root/.cache /root/.bash_history /usr/share/man/* /usr/share/doc/*
EODOC
    mkdir -p ${type}-${arch}/docker/ && cat <<'EODOC' >${type}-${arch}/docker/entrypoint.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

export LDAP_DOMAIN="${LDAP_DOMAIN:-sample.org}"
export LDAP_PASSWORD="${LDAP_PASSWORD:-${LDAP_DOMAIN}@PASS00}"

export LDAP_CFG_DIR="/etc/ldap/slapd.d"
export LDAP_RUN_DIR="/var/run/slapd"
export LDAP_BACKEND_DIR="/var/lib/ldap"
export LDAP_MOD_DIR="/usr/lib/ldap"
export LDAP_SCHEMA_DIR="/etc/ldap/schema"
export LDAP_PASSWORD_SSHA=$(slappasswd -u -h '{SSHA}' -s ${LDAP_PASSWORD})
export LDAP_SUFFIX="dc=$(echo ${LDAP_DOMAIN} | sed 's/^\.//; s/\./,dc=/g')"
[ -d ${LDAP_CFG_DIR}/cn=config ] || {
    rm -fvr ${LDAP_CFG_DIR}/* ${LDAP_RUN_DIR}/* ${LDAP_BACKEND_DIR}/*
    install -v -d -m 0755 --group=openldap --owner=openldap ${LDAP_CFG_DIR}
    install -v -d -m 0755 --group=openldap --owner=openldap ${LDAP_RUN_DIR}
    cat<<EO_LDIF | su openldap -s /bin/bash -c "slapadd -n0 -F ${LDAP_CFG_DIR}"
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
    cat<<EO_LDIF | su openldap -s /bin/bash -c "slapadd -n1 -F ${LDAP_CFG_DIR}"
dn: ${LDAP_SUFFIX}
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
}
echo "cn=admin,${LDAP_SUFFIX} ${LDAP_PASSWORD}"
ulimit -n 1024 && exec "$@"
EODOC
    chmod 755 ${type}-${arch}/docker/entrypoint.sh
    cat <<EODOC >> ${type}-${arch}/Dockerfile
VOLUME ["/etc/ldap/slapd.d", "/etc/ldap/ssl", "/var/lib/ldap", "/run/slapd"]
EXPOSE 10389
ENTRYPOINT ["/entrypoint.sh"]
CMD ["slapd", "-h", "ldapi:/// ldap://:10389/", "-u", "openldap", "-g", "openldap", "-d", "none"]
EODOC
    ################################################
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --name ${type}-${arch}.baseimg --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m || true
    rm -f ${type}-${arch}.baseimg.tpl || true
    docker export ${type}-${arch}.baseimg | mksquashfs - ${type}-${arch}.baseimg.tpl -tar # -quiet
    docker rm -v ${type}-${arch}.baseimg
    log "Pre chroot, copy files in ${type}-${arch}/docker/"
    #####
    log "Pre chroot exit"
    ./tpl_overlay.sh -t ${type}-${arch}.baseimg.tpl -r ${type}-${arch}.rootfs --upper ${type}-${arch}/docker
    log "chroot ${type}-${arch}.rootfs,(copy app) exit continue build"
    chroot ${type}-${arch}.rootfs /usr/bin/env -i SHELL=/bin/bash PS1="\u@DOCKER-${arch}:\w$" TERM=${TERM:-} COLORTERM=${COLORTERM:-} /bin/bash --noprofile --norc -o vi || true
    log "exit ${type}-${arch}.rootfs"
    ./tpl_overlay.sh -r ${type}-${arch}.rootfs -u
    log "Post chroot, delete nouse file in ${type}-${arch}/docker/"
    for fn in tmp root build.run nginx-johnyin_${arch}.deb; do
        rm -fr ${type}-${arch}/docker/${fn}
    done
    rm -vfr ${type}-${arch}.baseimg.tpl ${type}-${arch}.rootfs
done
log '=================================================='
for arch in ${ARCH[@]}; do
    log docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    log ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
    log docker push ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
done
log ./make_docker_image.sh -c combine --tag ${REGISTRY}/${nsname}/${type}:${ver}

trap "exit -1" SIGINT SIGTERM
read -n 1 -t 10 -p "Continue build(Y/n)? 10s timeout, default n" value || true
if [ "${value}" = "y" ]; then
    for arch in ${ARCH[@]}; do
        docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
        ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
        docker push ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
    done
    ./make_docker_image.sh -c combine --tag ${REGISTRY}/${nsname}/${type}:${ver}
fi
