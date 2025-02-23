#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
##OPTION_START##
PASSWORD=${PASSWORD:-}
CEPH=${CEPH:-}
PROXY=${PROXY:-}
# # PROXY=https://gcr.io
# # PROXY=https://quay.io
# # PROXY=https://registry.k8s.io
# # PROXY=https://registry-1.docker.io
# # PROXY=https://registry.aliyuncs.com
PORT=${PORT:-127.0.0.1:5000}
# # PORT=:6000
##OPTION_END##
show_option() {
    local file="${1}"
    sed -n '/^##OPTION_START/,/^##OPTION_END/p' ${file} | while IFS= read -r line; do
        [[ ${line} =~ ^\ *#.*$ ]] && continue #skip comment line
        [[ ${line} =~ ^\ *$ ]] && continue #skip blank
        eval "printf '%-16.16s = %s\n' \"${line%%=*}\" \"\${${line%%=*}:-UNSET}\""
    done
}
mkdir -p "${DIRNAME}/data"

[ -z "${PASSWORD}" ] || htpasswd -Bbn admin ${PASSWORD} > ${DIRNAME}/registry.password
echo 'https://github.com/distribution/distribution'
[ -e "${DIRNAME}/config.yml" ] && {
    addr=$(cat "${DIRNAME}/config.yml" | awk  '/addr:/{ print $2 }')
    echo "Start registry, ${addr}"
    nohup "${DIRNAME}/registry" serve "${DIRNAME}/config.yml"  &>${DIRNAME}/out.log &
} || {
    show_option "${0}"
    echo "Generate ${DIRNAME}/config.yml, rerun to start it"
    cat <<EOF > "${DIRNAME}/config.yml"
version: 0.1
log:
  # level: debug
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
$([ -z "${CEPH}" ] && {
    cat <<EOFS
  filesystem:
    rootdirectory: ${DIRNAME}/data
EOFS
} || {
    cat <<EOFS
  s3:
    region: default
    accesskey: I3FQV62N89SJLCVJX8OV
    secretkey: SeNoU5ou95Uwi4nZk01MACmmbniLoA608TeUauY0
    bucket: docker-registry
    rootdirectory: /registry-v2
    regionendpoint: http://10.170.24.3
    encrypt: false
    secure: false
    chunksize: 33554432
    secure: true
    v4auth: true
EOFS
})
  delete:
    enabled: true
      #  readonly:
      #    enabled: false
http:
  addr: ${PORT}
  headers:
    X-Content-Type-Options: [nosniff]
$([ -z "${PASSWORD}" ] || {
    cat <<EOAUTH
auth:
  htpasswd:
    realm: basic-realm
    path: ${DIRNAME}/registry.password
EOAUTH
})
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
$([ -z "${PROXY}" ] || {
    cat <<EOPROXY
proxy:
  remoteurl: ${PROXY}
  # username: [username]
  # password: [password]
  # 120.55.105.209 registry.aliyuncs.com
  # 47.97.242.13 dockerauth.cn-hangzhou.aliyuncs.com
  # 183.131.227.249 aliregistry.oss-cn-hangzhou.aliyuncs.com
EOPROXY
})
EOF
}
cat <<EOF
# # https://distribution.github.io/distribution/about/configuration/
# auth:
#   token:
#     realm: "https://auth-server:5001/auth"
#     service: "my.docker.registry"
#     issuer: "Acme auth server"
#     rootcertbundle: /certs/auth.crt
#
# redis:
#   tls:
#     certificate: /path/to/cert.crt
#     key: /path/to/key.pem
#     clientcas:
#       - /path/to/ca.pem
#   addrs: [localhost:6379]
#   password: asecret
#   db: 0
#   dialtimeout: 10ms
#   readtimeout: 10ms
#   writetimeout: 10ms
#   maxidleconns: 16
#   poolsize: 64
#   connmaxidletime: 300s
#   tls:
#     enabled: false
EOF
