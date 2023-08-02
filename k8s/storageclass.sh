#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("6cb8ef2[2023-08-01T10:47:01+08:00]:storageclass.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
set_sc_default() {
    local name=${1}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl get sc || true
    kubectl patch storageclass ${name} -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
}
sc_glusterfs() {
    cat <<EOF
apiVersion: v1
kind: Endpoints
metadata:
  name: glusterfs-cluster
  namespace: default
subsets:
- addresses:
  - ip: 192.168.16.173
  - ip: 192.168.16.174
  - ip: 192.168.16.175
  ports:
  - port: 49152
    protocol: TCP
EOF
}
sc_nfs() {
    local sc_name=${1}
    local nfs_server=${2}
    local nfs_path=${3}
    local name_space=${4}
    local insec_registry=192.168.168.250
    local provisioner_name=k8s-sigs.io/nfs-subdir-external-provisioner # 和StorageClass中provisioner保持一致便可
    # unexpected error getting claim reference: selfLink was empty, can't make reference
    # /etc/kubernetes/manifests/kube-apiserver.yaml 添加参数
    # 增加 - --feature-gates=RemoveSelfLink=false
    # kubectl apply -f /etc/kubernetes/manifests/kube-apiserver.yaml
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl create namespace ${name_space} &>/dev/null || true
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
  namespace: ${name_space}
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["create", "delete", "get", "list", "watch", "patch", "update"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: ${name_space}
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: ${name_space}
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: ${name_space}
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: ${name_space}
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io
EOF
cat << EOF | kubectl apply -f -
kind: Deployment
apiVersion: apps/v1
metadata:
  name: nfs-client-provisioner
  labels:
    app: nfs-client-provisioner
  namespace: ${name_space}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-client-provisioner
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          # quay.io/external_storage/nfs-client-provisioner:latest
          # registry.k8s.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
          image: ${insec_registry}/external_storage/nfs-client-provisioner:latest
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: ${provisioner_name}
            - name: NFS_SERVER
              value: ${nfs_server}
            - name: NFS_PATH
              value: ${nfs_path}
      volumes:
        - name: nfs-client-root
          nfs:
            server: ${nfs_server}
            path: ${nfs_path}
EOF
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${sc_name}
  namespace: ${name_space}
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ${provisioner_name}
EOF
    kubectl get sa
    kubectl get sc
    # archiveOnDelete: backup when delete
}
sc_rbd() {
    local name=${1}
    local mons=${2} # srv1:6789,srv2:6789
    local admin_id=${3}
    local secretname=${4}
    local pool=${5}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "create rbd-provisioner"
# https://docs.ceph.com/en/latest/rbd/rbd-kubernetes/
# ceph auth get-key client.admin
# ceph auth add client.kube mon 'allow r' osd 'allow rwx pool=k8spool'
# ceph auth get-key client.kube
# kubectl create secret generic ceph-user-secret --type="kubernetes.io/rbd" --from-literal=key='<key>' --namespace=kube-system
# kubectl create secret generic ceph-admin-secret --type="kubernetes.io/rbd" --from-literal=key='<key>' --namespace=kube-system
# kubectl get secrets ceph-user-secret -n kube-system
# kubectl get secrets ceph-admin-secret -n kube-system
}
sc_local() {
    local name=${1}
    local node=${2}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${name}
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
# Local volumes do not currently support dynamic provisioning
# Local storageClass 动态生成pv，手动创建pv
# provisioner: kubernetes.io/gce-pd
EOF
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-${name}
spec:
  capacity:
    storage: 25Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: ${name}
  local:
    path: /data/k8s  # node节点上的目录
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node}
EOF
}
init_pvc() {
    local name=${1}
    local scname=${2}
    local mode=${3}
    local name_space=${4:-default}
    # ReadWriteOnce
    # ReadWriteMany
    export KUBECONFIG=/etc/kubernetes/admin.conf
    # ReadWriteOnce：可以被一个node读写
    # ReadOnlyMany：可以被多个node读取
    # ReadWriteMany：可以摆多个node读写
    cat<<EOF | kubectl apply -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ${name}
  namespace: ${name_space}
spec:
  accessModes:
  - ${mode}
  resources:
    requests:
      storage: 25Gi
  storageClassName: ${scname}
EOF
    kubectl get pvc -n ${name_space} ${name}
}
test_dynamic_pvc() {
    cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-pod
  namespace: default
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
      - name: my-pvc-nfs
        persistentVolumeClaim:
          claimName: ${pvc_name}
      containers:
      - name: example-storage
        image: 192.168.168.250/library/busybox:latest
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c']
        args: ['echo "The host is \$(hostname)" >> /dir/data; sleep 3600']
        volumeMounts:
        - name: my-pvc-nfs # template.spec.volumes[].name
          mountPath: /dir # mount inside of container
          readOnly: false
EOF
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -m|--master      *  <ip>    master ipaddr
        -t|--sctype      *  <str>   local/nfs/rbd
        -n|--name        *  <str>   storageclass name
        --default                   as default storageclass
        --store-node        <node>  local storageclass store node
        --nfs-server        <str>   nfs sc server
        --nfs-path          <path>  nfs sc path
        --nfs-readonly              nfs sc readonly
        -U|--user           <user>  master ssh user, default root
        -P|--port           <int>   master ssh port, default 60022
        --sshpass           <str>   master ssh password, default use keyauth
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local master="" sctype="" name="" default="" user=root port=60022
    local nfs_server="" nfs_path="" nfs_namespace="default"
    local store_node=""
    local opt_short="m:t:n:U:P:"
    local opt_long="master:,sctype:,name:,default,user:,port:,sshpass:,nfs-server:,nfs-path:,nfs-readonly,store-node:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)    shift; master=${1}; shift;;
            -t | --sctype)    shift; sctype=${1}; shift;;
            -n | --name)      shift; name=${1}; shift;;
            --default)        shift; default=1;;
            --store-node)     shift; store_node=${1}; shift;;
            --nfs-server)     shift; nfs_server=${1}; shift;;
            --nfs-path)       shift; nfs_path=${1}; shift;;
            --nfs-namespace)   shift; nfs_namespace=1;;
            -U | --user)      shift; user=${1}; shift;;
            -P | --port)      shift; port=${1}; shift;;
            --sshpass)        shift; set_sshpass "${1}"; shift;;
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
    [ -z "${name}" ] || [ -z "${sctype}" ] || [ -z "${master}" ] && usage "master/sctype/name must input"
    case "${sctype}" in
        local)
            [ -z "${store_node}" ] && usage "local sc need store_node"
            ssh_func "${user}@${master}" "${port}" sc_local "${name}" "${store_node}"
            ssh_func "${user}@${master}" "${port}" init_pvc "pvc-${name}" "${name}" "ReadWriteOnce"
            ;;
        nfs)
            [ -z "${nfs_server}" ] || [ -z "${nfs_path}" ] && usage "nfs sc need server/path"
            ssh_func "${user}@${master}" "${port}" sc_nfs "${name}" "${nfs_server}" "${nfs_path}" "${nfs_namespace}"
            ssh_func "${user}@${master}" "${port}" init_pvc "pvc-${name}" "${name}" "ReadWriteMany"
            ;;
        rbd)
            exit_msg "rbd storageclass n/a now!\n"
            ssh_func "${user}@${master}" "${port}" sc_rbd "${name}"
            ;;
        glusterfs)
            ;;
        *)     usage "unsupport sctype: ${sctype}";;
    esac
    [ -z "${default}" ] || ssh_func "${user}@${master}" "${port}" set_sc_default "${name}"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"

