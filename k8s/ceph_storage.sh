#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("348fb25[2023-08-13T13:54:09+08:00]:ceph_storage.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
CEPH_CSI_PROVISIONER_RBAC="https://raw.githubusercontent.com/ceph/ceph-csi//v3.8.1/deploy/rbd/kubernetes/csi-provisioner-rbac.yaml"
CEPH_CSI_NODEPLUGIN_RBAC="https://raw.githubusercontent.com/ceph/ceph-csi//v3.8.1/deploy/rbd/kubernetes/csi-nodeplugin-rbac.yaml"
CEPH_CSI_RBDPLUGIN_PROVISIONER="https://raw.githubusercontent.com/ceph/ceph-csi//v3.8.1/deploy/rbd/kubernetes/csi-rbdplugin-provisioner.yaml"
CEPH_CSI_RBDPLUGIN="https://raw.githubusercontent.com/ceph/ceph-csi//v3.8.1/deploy/rbd/kubernetes/csi-rbdplugin.yaml"

L_CEPH_CSI_PROVISIONER_RBAC="csi-provisioner-rbac.yaml"
L_CEPH_CSI_NODEPLUGIN_RBAC="csi-nodeplugin-rbac.yaml"
L_CEPH_CSI_RBDPLUGIN_PROVISIONER="csi-rbdplugin-provisioner.yaml"
L_CEPH_CSI_RBDPLUGIN="csi-rbdplugin.yaml"

R_CEPH_CSI_PROVISIONER_RBAC="$(mktemp)"
R_CEPH_CSI_NODEPLUGIN_RBAC="$(mktemp)"
R_CEPH_CSI_RBDPLUGIN_PROVISIONER="$(mktemp)"
R_CEPH_CSI_RBDPLUGIN="$(mktemp)"

set_sc_default() {
    local name=${1}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl get sc || true
    kubectl patch storageclass ${name} -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
}

inst_ceph_csi_configmap() {
    local csi_ns=${1}
    local clusterid=${2}
    local rbd_user=${3}
    local sec_key=${4}
    shift 4
    printf -v mons "\"%s\"," "$@"
    mons=${mons%?}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl create namespace ${csi_ns} || true
cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: cephcsi
  name: cephcsi
EOF
    cat <<EOF | kubectl apply -f -
---
# csi-config-map
apiVersion: v1
kind: ConfigMap
data:
  config.json: |-
    [
      {
        "clusterID": "${clusterid}",
        "monitors": [ ${mons} ]
      }
    ]
metadata:
  name: ceph-csi-config
  namespace: ${csi_ns}
---
# csi-kms-config-map
apiVersion: v1
kind: ConfigMap
data:
  config.json: |-
    {}
metadata:
  name: ceph-csi-encryption-kms-config
  namespace: ${csi_ns}
---
# ceph-config-map
apiVersion: v1
kind: ConfigMap
data:
  ceph.conf: |
    [global]
    auth_cluster_required = cephx
    auth_service_required = cephx
    auth_client_required = cephx
  # keyring is a required key and its value should be empty
  keyring: |
metadata:
  name: ceph-config
  namespace: ${csi_ns}
---
# csi-rbd-secret
apiVersion: v1
kind: Secret
stringData:
  userID: ${rbd_user}
  userKey: ${sec_key}
metadata:
  name: csi-rbd-secret
  namespace: ${csi_ns}
EOF
}
inst_ceph_csi_provisioner() {
    local provisioner_rbac=${1}
    local nodeplugin_rbac=${2}
    local rbdplugin_provisioner=${3}
    local rbdplugin=${4}
    local csi_ns=${5}
    local insec_registry=${6}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    [ -z "${insec_registry}" ] || {
        sed -i "s|image\s*:\s*.*/sig-storage/|image: ${insec_registry}/sig-storage/|g" "${rbdplugin_provisioner}"
        sed -i "s|image\s*:\s*.*/cephcsi/|image: ${insec_registry}/cephcsi/|g"         "${rbdplugin_provisioner}"
        sed -i "s|image\s*:\s*.*/sig-storage/|image: ${insec_registry}/sig-storage/|g" "${rbdplugin}"
        sed -i "s|image\s*:\s*.*/cephcsi/|image: ${insec_registry}/cephcsi/|g"         "${rbdplugin}"
    }
    sed -i "s|namespace\s*:.*|namespace: ${csi_ns}|g" "${provisioner_rbac}"
    sed -i "s|namespace\s*:.*|namespace: ${csi_ns}|g" "${nodeplugin_rbac}"
    sed -i "s|namespace\s*:.*|namespace: ${csi_ns}|g" "${rbdplugin_provisioner}"
    sed -i "s|namespace\s*:.*|namespace: ${csi_ns}|g" "${rbdplugin}"
    kubectl apply -f "${provisioner_rbac}"
    kubectl apply -f "${nodeplugin_rbac}"
    kubectl apply -f "${rbdplugin_provisioner}"
    kubectl apply -f "${rbdplugin}"
    rm -f  "${provisioner_rbac}" "${nodeplugin_rbac}" "${rbdplugin_provisioner}" "${rbdplugin}" || true
}
create_ceph_sc() {
    local csi_ns=${1}
    local clusterid=${2}
    local pool=${3}
    local sc_name=${4}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    cat <<EOF | kubectl apply -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: ${sc_name}
   annotations:
     storageclass.kubesphere.io/supported-access-modes: '["ReadWriteOnce","ReadOnlyMany","ReadWriteMany"]'
provisioner: rbd.csi.ceph.com
parameters:
   clusterID: ${clusterid}
   pool: ${pool}
   imageFeatures: layering
   csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
   csi.storage.k8s.io/provisioner-secret-namespace: ${csi_ns}
   csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
   csi.storage.k8s.io/controller-expand-secret-namespace: ${csi_ns}
   csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
   csi.storage.k8s.io/node-stage-secret-namespace: ${csi_ns}
   csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
   - discard
EOF
}
create_ceph_pvc() {
    local sc_name=${1}
    local pvc_name_block=${2}
    local pvc_name_fs=${3}
    local pvc_size=${4}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    cat <<EOF | kubectl apply -f -
---
# raw-block mode rbd pvc
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name_block}
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Block
  resources:
    requests:
      storage: ${pvc_size}
  storageClassName: ${sc_name}
---
# filesystem mode rbd pvc
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name_fs}
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: ${pvc_size}
  storageClassName: ${sc_name}
EOF
}
test_demo() {
    local pvc_name_block=${1}
    local pvc_name_fs=${2}
    local insec_registry=${3:-}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-pod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: busybox
  template:
    metadata:
      labels:
        app: busybox
    spec:
      volumes:
      - name: rbd-device
        persistentVolumeClaim:
          claimName: ${pvc_name_block}
      - name: rbd-fs
        persistentVolumeClaim:
          claimName: ${pvc_name_fs}
      containers:
      - name: storage-test
        image: ${insec_registry:+${insec_registry}/}library/busybox:latest
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c']
        args: ["tail -f /dev/null"]
        volumeDevices:
        - name: rbd-device
          devicePath: /dev/xvda
        volumeMounts:
        - name: rbd-fs
          mountPath: /dir
EOF
}
# remote execute function end!
################################################################################
prepare_yml() {
    local user=${1}
    local port=${2}
    local ipaddr=${3}
    local local_yml=${4}
    local remote_yml=${5}
    local yml_url=${6}
    [ -e "${local_yml}" ] && {
        upload "${local_yml}" "${ipaddr}" "${port}" "${user}" "${remote_yml}"
    } || {
        warn_msg "Local yaml ${local_yml} NOT EXIST!!, remote download it.\n"
        ssh_func "${user}@${ipaddr}" "${port}" "wget -q ${yml_url} -O ${remote_yml}"
        download ${ipaddr} "${port}" "${user}" "${remote_yml}" "${local_yml}"
    }
}
inst_ceph_csi() {
    local user=${1}
    local port=${2}
    local master=${3}
    local csi_ns=${4}
    local insec_registry=${5}
    local clusterid=${6}
    local rbd_user=${7}
    local sec_key=${8}
    shift 8
    local mon=$@
    vinfo_msg <<EOF
****** ${master} init ceph csi storage
csi_namespace=${csi_ns}
registry=${insec_registry}
clusterid=${clusterid}
rbd_user=${rbd_user}
secrity_key=${sec_key}
mon=${mon}
EOF
    prepare_yml "${user}" "${port}" "${master}" "${L_CEPH_CSI_PROVISIONER_RBAC}" "${R_CEPH_CSI_PROVISIONER_RBAC}" "${CEPH_CSI_PROVISIONER_RBAC}"
    prepare_yml "${user}" "${port}" "${master}" "${L_CEPH_CSI_NODEPLUGIN_RBAC}" "${R_CEPH_CSI_NODEPLUGIN_RBAC}" "${CEPH_CSI_NODEPLUGIN_RBAC}"
    prepare_yml "${user}" "${port}" "${master}" "${L_CEPH_CSI_RBDPLUGIN_PROVISIONER}" "${R_CEPH_CSI_RBDPLUGIN_PROVISIONER}" "${CEPH_CSI_RBDPLUGIN_PROVISIONER}"
    prepare_yml "${user}" "${port}" "${master}" "${L_CEPH_CSI_RBDPLUGIN}" "${R_CEPH_CSI_RBDPLUGIN}" "${CEPH_CSI_RBDPLUGIN}"
    ssh_func "${user}@${master}" "${port}" inst_ceph_csi_configmap "${csi_ns}" "${clusterid}" "${rbd_user}" "${sec_key}" ${mon}
    ssh_func "${user}@${master}" "${port}" inst_ceph_csi_provisioner "${R_CEPH_CSI_PROVISIONER_RBAC}" "${R_CEPH_CSI_NODEPLUGIN_RBAC}" "${R_CEPH_CSI_RBDPLUGIN_PROVISIONER}" "${R_CEPH_CSI_RBDPLUGIN}" "${csi_ns}" "${insec_registry}"
}
teardown() {
    local user=${1}
    local port=${2}
    local master=${3}
    local csi_ns=${4}
    local sc=${5}
    cat "${L_CEPH_CSI_RBDPLUGIN}" | ssh_func "${user}@${master}" "${port}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete -f -" || true
    cat "${L_CEPH_CSI_RBDPLUGIN_PROVISIONER}" | ssh_func "${user}@${master}" "${port}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete -f -" || true
    cat "${L_CEPH_CSI_NODEPLUGIN_RBAC}" | ssh_func "${user}@${master}" "${port}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete -f -" || true
    cat "${L_CEPH_CSI_PROVISIONER_RBAC}" | ssh_func "${user}@${master}" "${port}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete -f -" || true
    ssh_func "${user}@${master}" "${port}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete sc ${sc}" || true
    ssh_func "${user}@${master}" "${port}" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete namespace ${csi_ns}" || true
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
            SUDO=   default undefine
        -m|--master         *  <ip>       master nodes,single input
        -c|--clusterid      *  <uuid>     ceph fsid, ceph mon dump
        -u|--rbd_user          <str>      ceph rbd user, default admin, ceph auth get-key client.admin
        -k|--sec_key        *  <str>      rbd user key
        -M|--mon            *  <ip:port>  ceph mons, ip:6789, multi input
        --namespace            <str>      ceph csi k8s namespace
        --insec_registry       <str>      insecurity registry(http/no auth)
        -p|--pool           *  <rbd pool>
        --sc                   <str>      storageclass name, default: sc-ceph
        --default                         default storageclass
        --pvc_blk              <str>      ceph block device pvc name, default: pvc-blk-ceph
        --pvc_fs               <str>      ceph rbd fs pvc name, default: pvc-fs-ceph
        --pvc_size             <int>      int Gi size, if not input, not create pvc
        -U|--user              <user>     ssh user, default root
        -P|--port              <int>      ssh port, default 60022
        --password             <str>      ssh password(default use sshkey)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local master="" clusterid="" sec_key="" insec_registry="" teardown_master=""  pvc_size=""
    local csi_ns="ceph-storage" rbd_user="admin" sc_default=false
    local mon=()
    local pool="" sc="sc-ceph" pvc_blk="pvc-blk-ceph" pvc_fs="pvc-fs-ceph"
    local user=root port=60022
    local opt_short="m:c:u:k:M:p:U:P:"
    local opt_long="master:,clusterid:,rbd_user:,sec_key:,mon:,namespace:,insec_registry:,pool:,sc:,default,pvc_blk:,pvc_fs:,pvc_size:,user:,port:,password:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)    shift; master=${1}; shift;;
            -c | --clusterid) shift; clusterid=${1}; shift;;
            -u | --rbd_user)  shift; rbd_user=${1}; shift;;
            -k | --sec_key)   shift; sec_key=${1}; shift;;
            -M | --mon)       shift; mon+=(${1}); shift;;
            --namespace)      shift; csi_ns=${1}; shift;;
            --insec_registry) shift; insec_registry=${1}; shift;;
            -p | --pool)      shift; pool=${1}; shift;;
            --sc)             shift; sc=${1}; shift;;
            --default)        shift; sc_default=true;;
            --pvc_blk)        shift; pvc_blk=${1}; shift;;
            --pvc_fs)         shift; pvc_fs=${1}; shift;;
            --pvc_size)       shift; pvc_size=${1}Gi; shift;;
            -U | --user)       shift; user=${1}; shift;;
            -P | --port)       shift; port=${1}; shift;;
            --password)       shift; set_sshpass "${1}"; shift;;
            --teardown)       shift; teardown_master=${1}; shift;;
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
    [ -z "${teardown_master}" ] || { teardown "${user}" "${port}" "${teardown_master}" "${csi_ns}" "${sc}"; info_msg "TEARDOWN DONE\n"; return 0; }
    [ -z "${master}" ] || [ -z "${clusterid}" ] || [ -z "${sec_key}" ] || [ -z "${pool}" ] && usage "master/clusterid/sec_key/pool must input"
    [ "$(array_size mon)" -gt "0" ] || usage "at least one ceph mon"
    file_exists "${L_CEPH_CSI_PROVISIONER_RBAC}" && \
        file_exists "${L_CEPH_CSI_NODEPLUGIN_RBAC}"  && \
        file_exists "${L_CEPH_CSI_RBDPLUGIN_PROVISIONER}" && \
        file_exists "${L_CEPH_CSI_RBDPLUGIN}" || \
        confirm "${L_CEPH_CSI_PROVISIONER_RBAC}/${L_CEPH_CSI_NODEPLUGIN_RBAC}/${L_CEPH_CSI_RBDPLUGIN_PROVISIONER}/${L_CEPH_CSI_RBDPLUGIN} not exists, continue? (timeout 10,default N)?" 10 || exit_msg "BYE!\n"
    inst_ceph_csi "${user}" "${port}" "${master}" "${csi_ns}" "${insec_registry}" "${clusterid}" "${rbd_user}" "${sec_key}" ${mon[@]}
    info_msg "create storageclass: ${sc}, pool: ${pool}\n"
    ssh_func "${user}@${master}" "${port}" create_ceph_sc "${csi_ns}" "${clusterid}" "${pool}" "${sc}"
    ${sc_default} && ssh_func "${user}@${master}" "${port}" set_sc_default "${sc}"
    [ -z "${pvc_size}" ] || {
        info_msg "create pvc: ${pvc_blk},${pvc_fs}. size: ${pvc_size}\n"
        ssh_func "${user}@${master}" "${port}" create_ceph_pvc "${sc}" "${pvc_blk}" "${pvc_fs}" "${pvc_size}"
        test_demo "${pvc_blk}" "${pvc_fs}" "${insec_registry}"
    }
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
