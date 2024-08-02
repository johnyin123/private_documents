#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace
cat <<EOF
    The Network classifier cgroup provides an interface to
tag network packets with a class identifier (classid).

EOF
PID="${1:?process pid need input, $0 <pid> <gateway> [fwmark] # default fwmark=5000}"
GATEWAY="${2:?gateway need input, $0 <pid> <gateway> [fwmark] # default fwmark=5000}"
FWMARK="${3:-5000}"              # # 1 to 2147483647
RULE_TABLE="$((FWMARK%251+1))"   # # 1 to 252
CLASSID="${FWMARK}"              # # 0x00000001 to 0xFFFFFFFF
NETCLS_NAME="JOHNYIN-${FWMARK}"

log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

[[ "${FWMARK}" =~ ^[0-9]+$ ]] || { log "FWMARK should integer"; exit 1; }

log "PID=${PID}, GATEWAY=${GATEWAY}, FWMARK=${FWMARK}"
grep -q "${PID}" "/sys/fs/cgroup/net_cls/${NETCLS_NAME}/tasks" 2>/dev/null && {
    log "PID ${PID} already in netcls ${NETCLS_NAME}, gateway: ${GATEWAY}, fwmark: ${FWMARK}, ip rule: ${RULE_TABLE}"
    grep -q "$(printf %d ${CLASSID})" /sys/fs/cgroup/net_cls/${NETCLS_NAME}/net_cls.classid 2>/dev/null || {
        log "classid ${CLASSID} not match, $(cat /sys/fs/cgroup/net_cls/${NETCLS_NAME}/net_cls.classid)!!!, exit." 
        exit 1
    }
} || {
    log "create new netcls ${NETCLS_NAME}"
    log "CLEAR CMD: umount /sys/fs/cgroup/net_cls && rmdir /sys/fs/cgroup/net_cls"
    mkdir /sys/fs/cgroup/net_cls 2>/dev/null && mount -t cgroup -onet_cls net_cls /sys/fs/cgroup/net_cls || true
    mkdir -p /sys/fs/cgroup/net_cls/${NETCLS_NAME}
    echo ${CLASSID} > /sys/fs/cgroup/net_cls/${NETCLS_NAME}/net_cls.classid
}

log "add PID=${PID} in netcls cgroup tasks"
echo ${PID} > /sys/fs/cgroup/net_cls/${NETCLS_NAME}/tasks

for _pid in $(cat /sys/fs/cgroup/net_cls/${NETCLS_NAME}/tasks); do
    log "net_cls attached pid: ${_pid}: $(cat /proc/${_pid}/comm 2>/dev/null)"
done

ip rule show fwmark ${FWMARK} | grep -qE "lookup\s*${RULE_TABLE}" || {
    log "create new ip rules for netcls ${NETCLS_NAME}"
    ip route flush table ${RULE_TABLE} 2>/dev/null || true
    ip rule delete fwmark ${FWMARK} table ${RULE_TABLE} 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m cgroup --cgroup ${CLASSID} -j MARK --set-mark ${FWMARK} 2>/dev/null || true
    iptables -t nat -D POSTROUTING -m cgroup --cgroup ${CLASSID} -j MASQUERADE 2>/dev/null || true

    iptables -t mangle -A OUTPUT -m cgroup --cgroup ${CLASSID} -j MARK --set-mark ${FWMARK}
    iptables -t nat -A POSTROUTING -m cgroup --cgroup ${CLASSID} -j MASQUERADE

    # # iptables -A OUTPUT -m cgroup ! --cgroup ${CLASSID} -j DROP
    ip rule add fwmark ${FWMARK} table ${RULE_TABLE}
    ip route replace default via ${GATEWAY} table ${RULE_TABLE}
}
ip rule show fwmark ${FWMARK}
ip route show table ${RULE_TABLE}
log "ALL DONE"
