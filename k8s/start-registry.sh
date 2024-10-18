#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
PASSWORD=${PASSWORD:-}
mkdir -p "${DIRNAME}/data"
[ -z "${PASSWORD}" ] || htpasswd -Bbn admin ${PASSWORD} > ${DIRNAME}/registry.password

echo 'https://github.com/distribution/distribution'

cat <<EOF > "${DIRNAME}/config.yml"
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: ${DIRNAME}/data
  delete:
    enabled: true
      #  readonly:
      #    enabled: false
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
$([ -z "${PASSWORD}" ] || cat <<EOAUTH
auth:
  htpasswd:
    realm: basic-realm
    path: ${DIRNAME}/registry.password
EOAUTH
)
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
nohup "${DIRNAME}/registry" serve "${DIRNAME}/config.yml"  &>/dev/null &
