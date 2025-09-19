#!/usr/bin/env bash
redefine_pool() {
    local pool_name="${1}"
    local url="${2}"
    local dir="${3}"
    local VIRSH="virsh -c ${url}"
    ${VIRSH} pool-destroy ${pool_name} || true
    ${VIRSH} pool-delete ${pool_name} || true
    ${VIRSH} pool-undefine ${pool_name} || true
    cat <<EPOOL | tee | ${VIRSH} pool-define /dev/stdin
    <pool type='dir'>
      <name>${pool_name}</name>
      <target>
        <path>${dir}</path>
      </target>
    </pool>
EPOOL
    ${VIRSH} pool-start ${pool_name}
    ${VIRSH} pool-autostart ${pool_name}
}
#########################################3
srv=https://vmm.registry.local
echo 'init all host env' && {
    for url in $(curl -k ${srv}/tpl/host/ 2>/dev/null | jq -r '.[]|.url'); do
        redefine_pool "default" "${url}" "/storage"
    done
}
cat <<EOF
virsh pool-create-as default dir --target /storage
virsh pool-start default
virsh pool-autostart default
EOF
