#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
log() { echo "$(tput setaf ${COLOR:-141})$*$(tput sgr0)" >&2; }

INPUT_DIR=${1:?$(echo "input source config dirname, ETCD_PREFIX=/simple-kvm/work $0 <dir>"; exit 1;)}

ETCD_PREFIX=$(python3 -c 'import config; print(config.ETCD_PREFIX)' || true)
if [ "${ETCD_PREFIX}" == "None" ]; then
    log "ETCD_PREFIX = ${ETCD_PREFIX} quit"
    exit 1
fi
log "ETCD_PREFIX = ${ETCD_PREFIX}"
APPDBS=(devices.json golds.json hosts.json iso.json vars.json)
TPLDIRS=(actions devices domains meta)
for f in ${APPDBS[@]}; do
  key="${ETCD_PREFIX}/${f}"
  log "== ${key} ========="
  cat ${INPUT_DIR}/${f} | etcdctl put ${key}
done
for dn in ${TPLDIRS[@]}; do
    dir=${INPUT_DIR}/${dn}
    [ -d "${dir}" ] && {
        for fn in $(find -L ${dir} -type f); do
            key="${ETCD_PREFIX}${fn#${INPUT_DIR}}"
            log "install ${key}"
            cat ${fn} | etcdctl put ${key}
        done
    } || {
        log "${dir} directory not exists!!!"
    }
done

# srv=$(python3 -c 'import config; print(config.META_SRV)' || true)
cat <<'EOF'
# # dump all
ETCD_PREFIX=/simple-kvm/work
OUTPUT='./'
for key in $(etcdctl get --prefix "${ETCD_PREFIX}" --keys-only); do
    dir=$(dirname "${OUTPUT}/$key")
    echo "$key -> $dir"
    mkdir -p "${dir}"
    etcdctl get -w json "${key}" | jq -r '.kvs[0].value' | base64 -d > "${OUTPUT}/${key}"
done
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
ETCD_PREFIX=/simple-kvm/work ./gen_test.sh /home/johnyin/disk/mygit/github_private/kvm/docker-kvm
# DATA_DIR=/dev/shm/simple-kvm/work TOKEN_DIR=/dev/shm/simple-kvm/token gunicorn 'main:app'
EOF

