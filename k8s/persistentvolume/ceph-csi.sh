#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("34b2a2a[2024-12-28T16:04:57+08:00]:ceph-csi.sh")
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
            FILTER_CMD="cat" # output with common
            LOGFILE=         # out stdout to file
        --download        <version>    download csi version yaml then exit
        -C                <filename>   storgeclass yaml filename
        -D                <filename>   demo yaml filename
        -r|--registry     <str>        default 'registry.local'
        -n|--ns           <str>        namespace, default 'cephcsi' 
        -v|--csi          <version>    csi version, default 'v3.7.2'
        --fsid        *   <uuid>       ceph fsid 
        --mon         *   <ip:port>    ceph mon, multi input 
        --rbd         *   <str>        rbd pool name 
        --rbduser     *   <str>        rbd user
        --rbdkey      *   <str>        rbd user key
        --fs          *   <str>        cephfs name 
        --fsuser      *   <str>        cephfs user 
        --fskey       *   <str>        cephfs user key
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    ${SCRIPTNAME} \\
        --fsid f0510d24-a438-4ad4-8ab3-5c0cc75991eb \\
        --mon 172.16.0.156:6789 \\
        --mon 172.16.0.157:6789 \\
        --mon 172.16.0.158:6789 \\
        --fs tsdfs \\
        --fsuser tsdfs-admin \\
        --fskey 'AQCJSW9nyIIZHhAA24K3QsdMcIVaRfLLsvFI3A==' \\
        --rbd k8s-pool \\
        --rbduser k8s-pool-admin \\
        --rbdkey 'AQBdPm9nEDkTCBAAfQhwRD/m9NBMYwfZGiXKRw==' \\
        -C storage_class.yaml -D demo.yaml
-----------------------------------------------------------
$(sed -ne '/^##\s*Usage Start/,/^##\s*Usage End$/p' < $0)
-----------------------------------------------------------
EOF
    exit 1
}
gen_csi_config() {
    local ns="${1}"
    local fsid="${2}"
    shift 2
    local mon="${*}"
# mon="172.16.0.156:6789,172.16.0.157:6789,172.16.0.158:6789"
# "monitors": [ "$(echo "${mon}" | sed 's/,/","/g')" ],
    log "Generate ceph-csi-config" && cat <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-config
  namespace: ${ns}
data:
  config.json: |-
    [
      {
        # fsid=f0510d24-a438-4ad4-8ab3-5c0cc75991eb
        "clusterID": "${fsid}",
        "monitors": [ "$(echo "${mon}" | sed 's/ /","/g')" ],
        "cephFS": {
          # # subvolumeGroup, default csi, mds allow rws
          "subvolumeGroup": "csi"
        }
      }
    ]
EOF
}

gen_csi_encryption_kms_config() {
    local ns="${1}"
    log "Generate empty ceph-csi-encryption-kms-config" && cat <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-encryption-kms-config
  namespace: ${ns}
data:
  config.json: |-
    {}
EOF
}

gen_ceph_config() {
    local ns="${1}"
    log "Generate dummy ceph-config" && cat <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-config
  namespace: ${ns}
data:
  ceph.conf: |
    [global]
    auth_cluster_required = cephx
    auth_service_required = cephx
    auth_client_required = cephx
    fuse_big_writes = true
  # keyring is a required key and its value should be empty
  keyring: |
EOF
}

gen_csi_secret() {
    local ns="${1}"
    local type="${2}"
    local user="${3}"
    local key="${4}"
    log "Generate csi-${type}-secret" && cat <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: csi-${type}-secret
  namespace: ${ns}
stringData:
  encryptionPassphrase: test_passphrase
  userID: ${user}
  userKey: ${key}
EOF
    [ "${type}" == "cephfs" ] || return 0
    cat <<EOF
  # Required for statically provisioned cephfs volumes
  adminID: ${user}
  adminKey: ${key}
EOF
}

gen_storageclass() {
    local fsid="${1}"
    local type="${2}"
    local namespace="${3}"
    local type_parm="${4}"
    log "Generate ${type}-storage-class" && cat <<EOF
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${type}-storage-class
provisioner: ${type}.csi.ceph.com
# reclaimPolicy: Retain
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
parameters:
  clusterID: ${fsid}
  csi.storage.k8s.io/provisioner-secret-name: csi-${type}-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ${namespace}
  csi.storage.k8s.io/controller-expand-secret-name: csi-${type}-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ${namespace}
  csi.storage.k8s.io/node-stage-secret-name: csi-${type}-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ${namespace}
EOF
    case "${type}" in
        rbd)    echo "  pool: ${type_parm}";echo "  imageFeatures: layering";;
        cephfs) echo "  fsName: ${type_parm}";;
    esac
}

gen_csi_namespace() {
    local ns="${1}"
    log "Generate namespace ${ns}" && cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${ns}
EOF
}
####################### ####################### #######################
cephfs_test() {
    log "Generate testpod" 
    cat <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: block-rbd-pvc
spec:
  accessModes:
    # ReadWriteMany is only supported for Block PVC
    - ReadWriteOnce
  volumeMode: Block
  resources:
    requests:
      storage: 1Gi 
  storageClassName: rbd-storage-class
EOF
    cat <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: filesystem-rbd-pvc
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Gi
  storageClassName: rbd-storage-class
EOF
    cat <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cephfs-pvc
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 100Mi
  storageClassName: cephfs-storage-class
EOF
    cat <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: ceph-csi-test
spec:
  containers:
    - name: ceph-csi-test
      image: registry.local/debian:bookworm
      imagePullPolicy: IfNotPresent
      command: ["/usr/bin/busybox", "sleep", "infinity"]
      volumeMounts:
      - name: ceph-csi-rbdfs
        mountPath: /rbdfs
      volumeDevices:
      - name: ceph-csi-block
        devicePath: /dev/xvda
      volumeMounts:
      - name: ceph-csi-cephfs
        mountPath: /cephfs
  volumes:
    - name: ceph-csi-block
      persistentVolumeClaim:
        claimName: block-rbd-pvc
    - name: ceph-csi-rbdfs
      persistentVolumeClaim:
        claimName: filesystem-rbd-pvc
    - name: ceph-csi-cephfs
      persistentVolumeClaim:
        claimName: cephfs-pvc
EOF
}
####################### ####################### #######################
download() {
    csi_ver=${1}
    rbd=(
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/rbd/kubernetes/csidriver.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/rbd/kubernetes/csi-provisioner-rbac.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/rbd/kubernetes/csi-nodeplugin-rbac.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/rbd/kubernetes/csi-rbdplugin-provisioner.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/rbd/kubernetes/csi-rbdplugin.yaml
    )
    cephfs=(
        # # must check kubernetes & ceph version, Ceph CSI drivers must support!!
        # v3.8.0	Kubernetes	v1.24, v1.25, v1.26, v1.27
        # v3.7.2	Kubernetes	v1.22, v1.23, v1.24
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/cephfs/kubernetes/csidriver.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/cephfs/kubernetes/csi-cephfsplugin-provisioner.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/cephfs/kubernetes/csi-cephfsplugin.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/cephfs/kubernetes/csi-nodeplugin-rbac.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${csi_ver}/deploy/cephfs/kubernetes/csi-provisioner-rbac.yaml
    )
    for url in ${rbd[@]}; do
        fn="$(basename ${url})"
        log "download rbd ${url}"
        wget -q --no-check-certificate -O "rbd-${csi_ver}-${fn}" "${url}" || true
    done
    for url in ${cephfs[@]}; do
        fn="$(basename ${url})"
        log "download cephfs ${url}"
        wget -q --no-check-certificate -O "cephfs-${csi_ver}-${fn}" "${url}" || true
    done
    return 0
}
####################### ####################### #######################
main() {
    local registry="registry.local" namespace="cephcsi" csi_ver="v3.7.2"
    local fsid="" mon=()
    local rbd_pool="" rbd_user="" rbd_key=""
    local cephfs_name="" cephfs_user="" cephfs_key=""
    local sc="" demo=""
    local opt_short="p:f:C:D:"
    local opt_long="registry:,ns:,csi:,fsid:,mon:,rbd:,rbduser:,rbdkey:,fs:,fsuser:,fskey:,download:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --download)      shift; download "${1}"; return 0;shift;; 
            -C)              shift; sc="${1}"; shift;;
            -D)              shift; demo="${1}"; shift;;
            -r | --registry) shift; registry="${1}"; shift;;
            -n | --ns)       shift; namespace="${1}"; shift;;
            -v | --csi)      shift; csi_ver="${1}"; shift;;
            --fsid)          shift; fsid="${1}"; shift;;
            --mon)           shift; mon+=("${1}"); shift;;
            --rbd)           shift; rbd_pool="${1}"; shift;;
            --rbduser)       shift; rbd_user="${1}"; shift;;
            --rbdkey)        shift; rbd_key="${1}"; shift;;
            --fs)            shift; cephfs_name="${1}"; shift;;
            --fsuser)        shift; cephfs_user="${1}"; shift;;
            --fskey)         shift; cephfs_key="${1}"; shift;;
            ########################################
            -q | --quiet)   shift; FILTER_CMD=;;
            -l | --log)     shift; LOGFILE=${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    exec > >(${FILTER_CMD:-sed '/^\s*#/d'} | tee ${LOGFILE:+-i ${LOGFILE}})
    for type in rbd cephfs; do
        [ -e "${type}-${csi_ver}-csi-provisioner-rbac.yaml" ] || { log "${type}-${csi_ver}-csi-provisioner-rbac.yaml nofound"; exit 1; }
        [ -e "${type}-${csi_ver}-csi-nodeplugin-rbac.yaml" ] || { log "${type}-${csi_ver}-csi-nodeplugin-rbac.yaml nofound"; exit 1; }
        [ -e "${type}-${csi_ver}-csi-${type}plugin-provisioner.yaml" ] || { log "${type}-${csi_ver}-csi-${type}plugin-provisioner.yaml nofound"; exit 1; }
        [ -e "${type}-${csi_ver}-csi-${type}plugin.yaml" ] || { log "${type}-${csi_ver}-csi-${type}plugin.yaml nofound"; exit 1; }
        [ -e "${type}-${csi_ver}-csidriver.yaml" ] || { log "${type}-${csi_ver}-csidriver.yaml nofound"; exit 1; }
    done
    gen_csi_namespace "${namespace}"
    gen_csi_config "${namespace}" "${fsid}" ${mon[@]}
    gen_csi_encryption_kms_config "${namespace}"
    gen_ceph_config "${namespace}"
    gen_csi_secret "${namespace}" "rbd" "${rbd_user}" "${rbd_key}"
    gen_csi_secret "${namespace}" "cephfs" "${cephfs_user}" "${cephfs_key}"
    for type in rbd cephfs; do
        log "CSI modify ${type}-${csi_ver}"
        { 
            cat ${type}-${csi_ver}-csi-provisioner-rbac.yaml
            cat ${type}-${csi_ver}-csi-nodeplugin-rbac.yaml
            cat ${type}-${csi_ver}-csi-${type}plugin-provisioner.yaml
            cat ${type}-${csi_ver}-csi-${type}plugin.yaml
            cat ${type}-${csi_ver}-csidriver.yaml
        } | sed -E \
            -e "s/image\s*:\s*[^\/]*\//image: ${registry}\//g" \
            -e "s/namespace\s*:\s*.*/namespace: ${namespace}/g"
    done
    [ -z "${sc}" ] || {
        gen_storageclass "${fsid}" rbd "${namespace}" "${rbd_pool}" > "${sc}"
        gen_storageclass "${fsid}" cephfs "${namespace}" "${cephfs_name}" >> "${sc}"
    }
    [ -z "${demo}" ] || cephfs_test > "${demo}"
    log "csi cephfs yaml not include namespace, so need kubectl -n ...."
    log "kubectl create ns ${namespace}"
    log "kubectl -n ${namespace} apply -f <input>"
    return 0
}
main "$@"

:<<'EOF'
## Usage Start
FSID=$(ceph fsid)
CEPHFS_KEY=$(ceph auth get-key client.${CEPHFS_USER})
CEPHFS_NAME=$(ceph fs ls -f json | jq -r '.[0].name')
ceph config generate-minimal-conf > ceph.conf
fsname=$(ceph fs volume ls | jq -r '.[0].name')

# # RBD
    ceph osd pool create ${poolname} 128
    rbd pool init ${poolname}
    ceph auth get-or-create client.${poolname}-admin \
        mon 'profile rbd' \
        osd "profile rbd pool=${poolname}" \
        mgr "profile rbd pool=${poolname}"

# # CEPHFS
    ceph fs volume create ${fsname}
    # # "subvolumeGroup": "csi"
    ceph auth get-or-create client.${fsname}-admin \
      mgr "allow rw" \
      osd "allow rw tag cephfs metadata=${fsname}, allow rw tag cephfs data=${fsname}" \
      mds "allow r fsname=${fsname} path=/volumes, allow rws fsname=${fsname} path=/volumes/csi" \
      mon "allow r fsname=${fsname}"
    # # rpc error: code = Internal desc = rados: ret=-1, Operation not permitted
    # ceph fs authorize ${fsname} client.${fsname}-admin / rws

ceph auth get client.user
ceph auth get-key client.user

ceph fs subvolumegroup ls tsdfs
ceph fs subvolume ls tsdfs csi
ceph fs subvolume info tsdfs csi-vol-4b8d2f37-c4aa-11ef-b1f4-ce26a4bf360b csi

kubectl -n cephcsi exec -it csi-cephfsplugin-provisioner-xx -c csi-cephfsplugin -- /bin/bash
## Usage End
EOF
