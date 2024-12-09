#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("d2243d9[2024-12-06T16:18:39+08:00]:all-in-one.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
run_node() {
    echo '10.170.6.105  registry.local'>> /etc/hosts
    wget --no-check-certificate -O /etc/yum.repos.d/cnap.repo http://registry.local/cnap/cnap.repo
    yum -y --enablerepo=cnap install tsd_cnap_v1.23.17 bash-completion nfs-utils nfs4-acl-tools ceph-common multipath-tools open-iscsi
    # ctr -n k8s.io image  prune --all
}

worker_fast_store() {
    local disk=${1}
    yum -y install lvm2
    pvcreate ${disk}
    vgcreate k8sdata ${disk}
    lvcreate -l 100%FREE k8sdata -n lvcontainer
    mkfs.xfs -f -L container /dev/mapper/k8sdata-lvcontainer
    mkdir -p /var/lib/containerd/
    echo "UUID=$(blkid -s UUID -o value /dev/mapper/k8sdata-lvcontainer) /var/lib/containerd xfs noexec,nodev,noatime,nodiratime  0 2" >> /etc/fstab
    mount -a
}

master_fast_store() {
    local disk=${1}
    # parted -s /dev/vdb "mklabel gpt"
    # parted -s /dev/vdb "mkpart primary xfs 1M 100%"
    yum -y install lvm2
    pvcreate ${disk}
    vgcreate k8sdata ${disk}
    lvcreate -L 8G k8sdata -n lvetcd
    lvcreate -l 100%FREE k8sdata -n lvcontainer
    mkfs.xfs -f -L etc /dev/mapper/k8sdata-lvetcd
    mkfs.xfs -f -L container /dev/mapper/k8sdata-lvcontainer
    mkdir -p /var/lib/etcd/ /var/lib/containerd/
    echo "UUID=$(blkid -s UUID -o value /dev/mapper/k8sdata-lvetcd) /var/lib/etcd xfs noexec,nodev,noatime,nodiratime  0 2" >> /etc/fstab
    echo "UUID=$(blkid -s UUID -o value /dev/mapper/k8sdata-lvcontainer) /var/lib/containerd xfs noexec,nodev,noatime,nodiratime  0 2" >> /etc/fstab
    mount -a
}

master_nodes() {
    cat <<EOF
172.16.0.150
172.16.0.151
172.16.0.152
EOF
}

worker_nodes() {
    cat <<EOF
172.16.0.153
172.16.0.154
EOF
}

gen_inst_cmd() {
    cat <<EOF
./inst_k8s_via_registry.sh \\
$(for ip in $(master_nodes); do cat <<EO_CMD
    --master ${ip} \\
EO_CMD
done)
$(for ip in $(worker_nodes); do cat <<EO_CMD
    --worker ${ip} \\
EO_CMD
done)
    --calico IPIPCrossSubnet \\
    --ipvs \\
    --insec_registry registry.local \\
    --apiserver k8s.tsd.org:6443 \\
    --vip 172.16.0.155

./post-01-apiserver-ha.sh -m 172.16.0.150 -m 172.16.0.151 -m 172.16.0.152 --vip 172.16.0.155 --api_srv k8s.tsd.org
./post-10-calico_rr_ebpf.sh -m 172.16.0.150 -r node1 -r node2 -r node3 --ebpf k8s.tsd.org:60443
EOF
}

main() {
    for ip in $(master_nodes); do ssh_func root@${ip} 60022 master_fast_store "/dev/vdb"; done
    for ip in $(worker_nodes); do ssh_func root@${ip} 60022 worker_fast_store "/dev/vdb"; done
    for ip in $(master_nodes) $(worker_nodes); do ssh_func root@${ip} 60022 run_node; done
    gen_inst_cmd
}
main "$@"
