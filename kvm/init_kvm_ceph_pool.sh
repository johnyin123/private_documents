#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2023-05-11T16:55:23+08:00]:init_kvm_ceph_pool.sh")
################################################################################
libvirt_pool=default
ceph_mons=(192.168.168.201 192.168,168.202)
rbd_poolname=libvirt-pool
secret_name=client.libvirt
LOGFILE="-a log.txt"

ceph osd pool create ${rbd_poolname} 128
rbd pool init ${rbd_poolname}
ceph auth get-or-create ${secret_name} mon 'allow r' osd "allow class-read object_prefix rbd_children, allow rwx pool=${rbd_poolname}"
# all kvm nodes run: uuid 各个主机要使用一个
secret_uuid=$(cat /proc/sys/kernel/random/uuid)
echo "UUID=${secret_uuid}"
cat <<EPOOL | tee ${LOGFILE} | virsh secret-define /dev/stdin
<secret ephemeral='no' private='no'>
  <uuid>${secret_uuid}</uuid>
  <usage type='ceph'>
    <name>${secret_name} secret</name>
  </usage>
</secret>
EPOOL
secret_key=$(ceph auth get-key ${secret_name})
echo ${secret_key}
virsh secret-set-value --secret ${secret_uuid} --base64 ${secret_key}
cat <<EPOOL | tee ${LOGFILE} | virsh pool-define /dev/stdin
<pool type='rbd'>
  <name>${libvirt_pool}</name>
  <source>
$(for m in "${ceph_mons[@]}"; do echo "    <host name='${m}' port='6789'/>"; done)
    <name>${rbd_poolname}</name>
    <auth type='ceph' username='libvirt'>
      <secret uuid='${secret_uuid}'/>
    </auth>
  </source>
</pool>
EPOOL
# virsh pool-define-as ${libvirt_pool} --type rbd --source-host kvm01:6789,kvm02:6789,kvm03:6789 --source-name libv
virsh pool-start ${libvirt_pool}
virsh pool-autostart ${libvirt_pool}