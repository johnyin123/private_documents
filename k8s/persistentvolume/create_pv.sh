#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("d0fc26a[2024-11-27T14:48:30+08:00]:create_pv.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
        -t|--type     *   ${G}<str>${N}     PersistentVolume type(In-tree provisioning)
                          cephfs/rbd/iscsi/nfs/local, ${R}ALL CHECKED OK${N}
                          Out-tree: https://github.com/orgs/kubernetes-csi/repositories
        -n|--name         ${G}<str>${N}     PersistentVolume name, default YYYY-MM
        -s|--capacity     ${G}<str>${N}     PersistentVolume size, default 10G
        --default                           Set as default storageclass
        --annotation                        Output yaml with comment
        --namespace       ${G}<str>${N}     kubernetes namespace for pv,pvc,test-pod
        ${R}# # iscsi parm${N}
          --iscsi_user    ${G}<str>${N}     iscsi chap user
          --iscsi_pass    ${G}<str>${N}     iscsi chap password
          --iscsi_srv     ${G}<str>${N}     iscsi server with port list
                                            "172.16.0.156:3260 172.16.0.157:3260"
          --iscsi_iqn     ${G}<str>${N}     iscsi iqn
          --iscsi_lun     ${G}<str>${N}     iscsi lun num
        ${R}# # nfs parm${N}
          --nfs_srv       ${G}<str>${N}     nfs server address
          --nfs_path      ${G}<str>${N}     nfs path
        ${R}# # cephfs parm, v1.28 [deprecated], removed v1.31${N}
          --cephfs_path   ${G}<str>${N}     cephfs subpath, default /
        ${R}# # rbd parm, v1.28 [deprecated], removed v1.31${N}
          --rbd_pool      ${G}<str>${N}     rbd pool name
          --rbd_image     ${G}<str>${N}     rbd image name
          ${Y}# cephfs/rbd both use${N} --ceph_user --ceph_key --ceph_mons
          --ceph_user     ${G}<str>${N}     ceph user
          --ceph_key      ${G}<str>${N}     ceph auth key
          --ceph_mons     ${G}<str>${N}     ceph mons
                                            "172.16.16.3:6789 172.16.16.4:6789"
        ${R}# # local pv parm${N}
          --local_path    ${G}<str>${N}     host path
        -q|--quiet
        -l|--log ${G}<int>${N} log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    Exam:
        ${SCRIPTNAME} -t cephfs --ceph_user k9s --ceph_key 'AQAA5ENnWx2+DBAAC7ZpySjtYfXevBTlxw3AUg==' --cephfs_path '/k8s' --ceph_mons "172.16.16.2:6789 172.16.16.3:6789 172.16.16.4:6789"
        ${SCRIPTNAME} -t nfs --nfs_srv 172.16.0.152 --nfs_path /nfs_share
        ${SCRIPTNAME} -t iscsi --iscsi_srv "172.16.0.156:3260 172.16.0.157:3260" --iscsi_iqn "iqn.2024-11.rbd.local:iscsi-01" --iscsi_lun 1 --iscsi_user testuser --iscsi_pass 'password123'
        ${SCRIPTNAME} -t rbd --ceph_user k9s --ceph_key 'AQAA5ENnWx2+DBAAC7ZpySjtYfXevBTlxw3AUg==' --ceph_mons "172.16.16.2:6789 172.16.16.3:6789 172.16.16.4:6789" --rbd_pool 'k8s' --rbd_image rbd.img
        ${SCRIPTNAME} -t local --local_path /mnt/storage
EOF
)"; echo -e "${usage_doc}"
    exit 1
}

create_test_pod() {
    local type=${1}
    local name=${2}
    info_msg "Create test pod use pvc\n"
    vinfo_msg <<EOF
kubectl exec -it test-${type}-${name} -- cat /mnt/SUCCESS
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
---
apiVersion: v1
kind: Pod
metadata:
  name: test-${type}-${name}
  namespace: ${NAMESPACE:-default}
spec:
  containers:
  - name: test-${type}-${name}
    image: registry.local/debian:bookworm
    command:
      - "/bin/sh"
    args:
      - "-c"
      - "{ busybox date; busybox ip a; } > /mnt/SUCCESS && busybox sleep infinity || exit 1"
    volumeMounts:
    - mountPath: "/mnt"
      name: test-${type}-${name}-vol
  restartPolicy: "Never"
  volumes:
  - name: test-${type}-${name}-vol
    persistentVolumeClaim:
      claimName: pvc-${name}-${type}
EOF
}

set_default_storageclass() {
    local type=${1}
    local name=${2}
    vinfo_msg <<EOF
# Kubernetes doesn't include an internal NFS provisioner.
# You need to use an external provisioner to create a StorageClass for NFS.
kubectl api-resources
kubectl get storageclass
kubectl patch storageclass <name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
EOF
    [ -z "${PROVISIONER:-}" ] || cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
provisioner: ${PROVISIONER}
metadata:
  name: sc-${name}-${type}
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
#volumeBindingMode: WaitForFirstConsumer
EOF
}

create_pvc() {
    local type=${1}
    local name=${2}
    local capacity=${3:-100Mi}
    info_msg "Create PersistentVolumeClaim\n"
    vinfo_msg <<EOF
|---------------+----------------+---------|
| PV volumeMode | PVC volumeMode | Result  |
|---------------+----------------+---------|
| unspecified   | unspecified    | BIND    |
| unspecified   | Block          | NO BIND |
| unspecified   | Filesystem     | BIND    |
| Block         | unspecified    | NO BIND |
| Block         | Block          | BIND    |
| Block         | Filesystem     | NO BIND |
| Filesystem    | Filesystem     | BIND    |
| Filesystem    | Block          | NO BIND |
| Filesystem    | unspecified    | BIND    |
|---------------+----------------+---------|
# in a PVC:
If storageClassName="", then it is static provisioning
If storageClassName is not specified, then the default storage class will be used.
If storageClassName is set to a specific value, then the matching storageClassName will be considered. If no corresponding storage class exists, the PVC will fail.
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-${name}-${type}
  namespace: ${NAMESPACE:-default}
spec:
  accessModes:
    # # PV include PVC的AccessMode
    - ReadWriteOnce
  # # 卷的模式，Filesystem/Block，默认文件系统
  volumeMode: Filesystem
  resources:
    requests:
      # # PVC容量必须小于等于PV
      storage: ${capacity}
  # # PV与PVC的storageclass类名必须相同或同时为空
  storageClassName: sc-${name}-${type}
EOF
}

secret_common() {
    local type=${1}
    local name=${2}
    local user=${3}
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
---
apiVersion: v1
kind: Secret
metadata:
  name: ${type}-${name}-${user}-secret
  namespace: ${NAMESPACE:-default}
EOF
}

pv_common() {
    local type=${1}
    local name=${2}
    local capacity=${3}
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-${name}-${type}
  # # pv is cluster-scoped resources
  # namespace: ${NAMESPACE:-default}
spec:
  capacity:
    # # pv的容量
    storage: ${capacity}
  accessModes:
$(for mode in ${ACCESS_MODES:-NA}; do
cat <<EO_MODE
    - ${mode}
EO_MODE
done)
  # # 卷的模式，Filesystem/Block，默认文件系统
  volumeMode: Filesystem
  persistentVolumeReclaimPolicy: Retain
  # # Retain：保留，允许手动回收, 默认策略
  # # Delete：删除
  # # 存储类型的名称，pvc通过该名字访问到pv
  storageClassName: sc-${name}-${type}
EOF
}

create_pv_cephfs() {
    local name=${1}
    local capacity=${2}
    local ceph_user=${CEPH_USER:-}
    local ceph_key=${CEPH_KEY:-base64key}
    local cephfs_path=${CEPHFS_PATH:-/cephfs_path}
    local ceph_mons=${CEPH_MONS:-172.16.16.2:6789}
    info_msg "Create cephfs PersistentVolume\n"
    vinfo_msg <<'EOF'
client, k8s nodes:
    yum -y install ceph-common
    apt -y install ceph-common
ceph fs ls
ceph fs authorize <fsname> client.${ceph_user} /${cephfs_path} rw
ceph auth get-key client.${ceph_user}
ceph_key=uSlE9PQ==
mount -t ceph 172.16.16.3:6789:/cephfs_path /mnt/ -oname=${ceph_user},secret=${ceph_key}
mkdir -p /mnt/${cephfs_path}
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
$(secret_common "cephfs" "${name}" "${ceph_user}")
data:
  key: $(echo -n ${ceph_key} | base64)
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
$(pv_common cephfs "${name}" "${capacity}")
  cephfs:
    monitors:
$(for it in ${ceph_mons}; do
cat <<EO_MON
    - ${it}
EO_MON
done)
    user: ${ceph_user}
    path: ${cephfs_path}
    secretRef:
      name: cephfs-${name}-${ceph_user}-secret
    readOnly: false
EOF
}

create_pv_rbd() {
    local name=${1}
    local capacity=${2}
    local rbd_pool=${RBD_POOL:-dummy}
    local rbd_image=${RBD_IMAGE:-dummy.img}
    local ceph_user=${CEPH_USER:-}
    local ceph_key=${CEPH_KEY:-base64key}
    local ceph_mons=${CEPH_MONS:-172.16.16.2:6789}
    info_msg "Create rbd PersistentVolume\n"
    vinfo_msg <<'EOF'
USER=k8s
POOL_NAME=k8s-pool
ceph osd pool create ${POOL_NAME} 128
ceph auth get-or-create client.${USER} mon 'profile rbd' osd "profile rbd pool=${POOL_NAME}" mgr "profile rbd pool=${POOL_NAME}"
ceph mon stat
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
$(secret_common "rbd" "${name}" "${ceph_user}")
  key: $(echo -n ${ceph_key} | base64)
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
$(pv_common rbd "${name}" "${capacity}")
  rbd:
    monitors:
$(for it in ${ceph_mons}; do
cat <<EO_MON
    - ${it}
EO_MON
done)
    # # rbd pool. ceph osd pool ls
    pool: ${rbd_pool}
    # # rbd image. rbd create ${rbd_pool}/${rbd_image} --size 10G
    # # rbd list ${rbd_pool}
    image: ${rbd_image}
    user: ${ceph_user}
    secretRef:
      name: rbd-${name}-${ceph_user}-secret
    readOnly: false
    fsType: xfs
EOF
}

create_pv_iscsi() {
    local name=${1}
    local capacity=${2}
    local iscsi_user=${ISCSI_USER:-}
    local iscsi_pass=${ISCSI_PASS:-}
    local iscsi_srv=${ISCSI_SRV:-dummy-server-list}
    local iscsi_iqn=${ISCSI_IQN:-${name}.server-iscsi:server}
    local iscsi_lun=${ISCSI_LUN:-1}
    info_msg "Create iscsi PersistentVolume\n"
    vinfo_msg <<'EOF'
# # user tgt ceph impl iscsi multipath, seed ceph/ceph-iscsi-multipath.sh
iscsi server: yum install -y targetcli
targetcli ls
NAME=mylun0
PREFIX=iqn.2024-11.local
echo 'Create a backstore block device' && targetcli /backstores/block create ${NAME} /dev/vdb
# targetcli backstores/fileio/ create shareddata /storage/${NAME}.img 1024M
echo 'Create iSCSI for IQN target' && targetcli /iscsi create ${PREFIX}.server-iscsi:server
echo 'Create ACLs' && targetcli /iscsi/${PREFIX}.server-iscsi:server/tpg1/acls create ${PREFIX}.client-iscsi:client1
echo 'Create LUNs under the ISCSI target' && targetcli /iscsi/${PREFIX}.server-iscsi:server/tpg1/luns create /backstores/block/${NAME}
echo '1: CHAPP Authentication' && targetcli <<EO_CHAP
cd /iscsi/${PREFIX}.server-iscsi:server/tpg1
set attribute authentication=1
get attribute authentication
cd acls/${PREFIX}.client-iscsi:client1
set auth userid=testuser
set auth password=password123
get auth
ls
cd /
saveconfig
exit
EO_CHAP
# # OR
# echo '2: Create a specific IP address on Portal' && targetcli <<EO_CMD
# cd /iscsi/${PREFIX}.server-iscsi:server/tpg1/portals/
# createa <client ip>
# cd /iscsi/${PREFIX}.server-iscsi:server/tpg1/portals/
# delete 0.0.0.0 ip_port=3260
# create ${SERVER}
# ls
# saveconfig
# exit
# EO_CMD
systemctl restart target.service
========================================================================
client, k8s nodes:
        yum -y install multipath-tools open-iscsi && modprobe iscsi_tcp
        apt -y install multipath-tools open-iscsi && modprobe iscsi_tcp
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
$(secret_common "iscsi" "${name}" "${iscsi_user}")
type: kubernetes.io/iscsi-chap
data:
  # discovery.sendtargets.auth.username:
  # discovery.sendtargets.auth.password:
  # discovery.sendtargets.auth.username_in:
  # discovery.sendtargets.auth.password_in:
  node.session.auth.username: $(echo -n ${iscsi_user} | base64)
  node.session.auth.password: $(echo -n ${iscsi_pass} | base64)
  # node.session.auth.username_in:
  # node.session.auth.password_in:
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
$(pv_common iscsi "${name}" "${capacity}")
  iscsi:
$(SETONE=""; PORTALS=(); for srv in ${iscsi_srv};do
    [ -z "${SETONE}" ] && {
        SETONE="1"
        cat <<EO_PORTAL
    targetPortal: ${srv}
EO_PORTAL
        continue
    }
    PORTALS+=("'${srv}'")
done
    [ "${#PORTALS[@]}" -gt 0 ] && cat <<EO_PORTAL
    portals: [ $(join , "${PORTALS[@]}" ) ]
EO_PORTAL
)
    iqn: ${iscsi_iqn}
    lun: ${iscsi_lun}
    chapAuthSession: true
    secretRef:
      name: iscsi-${name}-${iscsi_user}-secret
    readOnly: false
    fsType: xfs
EOF
}

create_pv_nfs() {
    local name=${1}
    local capacity=${2}
    local nfs_path=${NFS_PATH:-/nfs_storage}
    local nfs_srv=${NFS_SRV:-nfsserver.local}
    info_msg "Create nfs PersistentVolume\n"
    vinfo_msg <<EOF
nfs server: yum -y install nfs-utils && systemctl start nfs-server.service && rpcinfo -p | grep nfs
mkdir -p ${nfs_path} && chown -R nobody:nobody ${nfs_path}
echo '${nfs_path} 172.16.0.0/24(rw,sync,no_all_squash,root_squash)' > /etc/exports
exportfs -arv
exportfs -s
nfs client(k8s nodes): yum -y install nfs-utils nfs4-acl-tools
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
$(pv_common nfs "${name}" "${capacity}")
  nfs:
    path: "${nfs_path}"
    server: "${nfs_srv}"
    readOnly: false
EOF
}

create_pv_local() {
    local name=${1}
    local capacity=${2}
    local local_path=${LOCAL_PATH:-/tmp}
    info_msg "Create local PersistentVolume\n"
    vinfo_msg <<EOF
LOCAL PV需要利用污点，让pod和宿主机强绑定
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
$(pv_common local "${name}" "${capacity}")
  hostPath:
    path: "${local_path}"
EOF
}

verify_pvtype() {
    local pvtype=${1}
    vinfo_msg <<EOF
|------------------+-------------------------------+----------------|
| ReadWriteOnce    | 单节点以读写模式挂载          | 命令行缩写RWO  |
| ReadOnlyMany     | 多个节点以只读模式挂载        | 命令行缩写ROX  |
| ReadWriteMany    | 多个节点以读写模式挂载        | 命令行缩写RWX  |
| ReadWriteOncePod | 只能被一个Pod以读写的模式挂载 | 命令中缩写RWOP |
|------------------+-------------------------------+----------------|
EOF
    PROVISIONER=kubernetes.io/${pvtype}
    case "${pvtype}" in
        cephfs) export ACCESS_MODES="ReadWriteOnce ReadWriteMany ReadOnlyMany"; return 0;;
        nfs)    export ACCESS_MODES="ReadWriteOnce ReadWriteMany ReadOnlyMany"; return 0;;
        rbd)    export ACCESS_MODES="ReadWriteOnce"; return 0;;
        iscsi)  export ACCESS_MODES="ReadWriteOnce"; return 0;;
        local)  export ACCESS_MODES="ReadWriteOnce ReadOnlyMany"; PROVISIONER=kubernetes.io/no-provisioner; return 0;;
        *)      exit_msg "unknow PersistentVolume type\n";;
    esac
}

main() {
    local pvtype="" capacity="10G" default=""
    local name="$(date +'%Y-%m')"
    local opt_short="t:n:s:"
    local opt_long="type:,name:,capacity:,annotation,default,"
    opt_long+="iscsi_user:,iscsi_pass:,iscsi_srv:,iscsi_iqn:,iscsi_lun:,"
    opt_long+="nfs_srv:,nfs_path:,";
    opt_long+="ceph_user:,ceph_key:,cephfs_path:,ceph_mons:,"
    opt_long+="rbd_pool:,rbd_image:,"
    opt_long+="local_path:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -t | --type)     shift; verify_pvtype "${1}" && pvtype=${1}; shift;;
            -n | --name)     shift; name=${1}; shift;;
            -s | --capacity) shift; capacity=${1}; shift;;
            --default)       shift; default=1;;
            --annotation)    shift; export FILTER_CMD=cat;;
                                  # export FILTER_CMD=tee output.log
            --namespace)     shift; export NAMESPACE="${1}"; shift;;
            # # iscsi env parm
            --iscsi_user)    shift; export ISCSI_USER="${1}"; shift;;
            --iscsi_pass)    shift; export ISCSI_PASS="${1}"; shift;;
            --iscsi_srv)     shift; export ISCSI_SRV="${1}"; shift;;
            --iscsi_iqn)     shift; export ISCSI_IQN="${1}"; shift;;
            --iscsi_lun)     shift; export ISCSI_LUN="${1}"; shift;;
            # # nfs env parm
            --nfs_srv)       shift; export NFS_SRV="${1}"; shift;;
            --nfs_path)      shift; export NFS_PATH="${1}"; shift;;
            # # cephfs env parm
            --cephfs_path)   shift; export CEPHFS_PATH="${1}"; shift;;
            # cephfs/rbd both use --ceph_user --ceph_key --ceph_mons
            --ceph_user)     shift; export CEPH_USER="${1}"; shift;;
            --ceph_key)      shift; export CEPH_KEY="${1}"; shift;;
            --ceph_mons)     shift; export CEPH_MONS="${1}"; shift;;
            # # rbd env parm
            --rbd_pool)      shift; export RBD_POOL="${1}"; shift;;
            --rbd_image)     shift; export RBD_IMAGE="${1}"; shift;;
            # # local env parm
            --local_path)    shift; export LOCAL_PATH="${1}"; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${pvtype}" ] && usage "type must input"
    [ -z "${default}" ] || set_default_storageclass "${pvtype}" "${name}"
    create_pv_${pvtype} "${name}" "${capacity}"
    create_pvc "${pvtype}" "${name}" "${capacity}"
    create_test_pod "${pvtype}" "${name}"
    return 0
}
main "$@"
