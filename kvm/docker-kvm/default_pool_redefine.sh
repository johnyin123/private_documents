#!/usr/bin/env bash
redefine_default() {
    local url="${1}"
    local pool_name=default
    local dir=/storage
    local VIRSH="virsh -c ${url}"
    ${VIRSH} pool-destroy ${pool_name}
    ${VIRSH} pool-delete ${pool_name}
    ${VIRSH} pool-undefine ${pool_name}
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
        redefine_default "${url}"
    done
}
