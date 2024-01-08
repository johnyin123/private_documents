#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
mkdir -p "${DIRNAME}/data"
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
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
nohup "${DIRNAME}/registry" serve "${DIRNAME}/config.yml"  &>/dev/null &

