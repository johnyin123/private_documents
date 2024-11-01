#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
PASSWORD=${PASSWORD:-}
CEPH=${CEPH:-}
PROXY=${PROXY:-}
mkdir -p "${DIRNAME}/data"

[ -z "${PASSWORD}" ] || htpasswd -Bbn admin ${PASSWORD} > ${DIRNAME}/registry.password

echo 'https://github.com/distribution/distribution'
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
  addr: 127.0.0.1:5000
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
  # remoteurl: https://registry.k8s.io
  # remoteurl: https://registry-1.docker.io
  remoteurl: https://registry.aliyuncs.com
# 120.55.105.209 registry.aliyuncs.com
# 47.97.242.13 dockerauth.cn-hangzhou.aliyuncs.com
# 183.131.227.249 aliregistry.oss-cn-hangzhou.aliyuncs.com
  # username: [username]
  # password: [password]
EOPROXY
})
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
nohup "${DIRNAME}/registry" serve "${DIRNAME}/config.yml"  &>/dev/null &
