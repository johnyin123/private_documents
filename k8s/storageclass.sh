#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("f46ff66[2023-07-27T16:40:18+08:00]:storageclass.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
set_sc_default() {
    local name=${1}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl get sc || true
    kubectl patch storageclass ${name} -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
}
sc_nfs() {
    local name=${1}
    local server=${2}
    local path=${3}
    local readonly=${4:-false}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${name}
  # annotations:
  #   storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs.csi.k8s.io
parameters:
  server: ${server}
  path: ${path}
  readOnly: "${readonly}"
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
    # archiveOnDelete: backup when delete
}
# adminId: Ceph client ID that is capable of creating images in the pool. Default is "admin".
# adminSecretName: Secret Name for adminId. This parameter is required. The provided secret must have type "kubernetes.io/rbd".
# adminSecretNamespace: The namespace for adminSecretName. Default is "default".
# pool: Ceph RBD pool. Default is "rbd".
# userId: Ceph client ID that is used to map the RBD image. Default is the same as adminId.
# userSecretName: The name of Ceph Secret for userId to map RBD image. It must exist in the same namespace as PVCs. This parameter is required. The provided secret must have type "kubernetes.io/rbd", for example created in this way:
#     ceph auth get-key client.kube
#     kubectl create secret generic ceph-secret --type="kubernetes.io/rbd" \
#       --from-literal=key='< key >' \
#       --namespace=kube-system
# userSecretNamespace: The namespace for userSecretName.
# fsType: fsType that is supported by kubernetes. Default: "ext4".
# imageFormat: Ceph RBD image format, "1" or "2". Default is "2".
# imageFeatures: This parameter is optional and should only be used if you set imageFormat to "2". Currently supported features are layering only. Default is "", and no features are turned on
sc_rbd() {
    local name=${1}
    local mons=${2} # srv1:6789,srv2:6789
    local admin_id=${3}
    local secretname=${4}
    local pool=${5}
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl create secret generic ceph-secret --type="kubernetes.io/rbd" \
      --from-literal=key="${key}" --namespace=kube-system
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${name}
provisioner: kubernetes.io/rbd
parameters:
  monitors: ${mons}
  adminId: ${admin_id}
  adminSecretName: ceph-secret
  adminSecretNamespace: kube-system
  pool: ${pool}
  userId: ${admin_id}
  userSecretName: ceph-secret-user
  userSecretNamespace: default
  fsType: ext4
  imageFormat: "2"
  imageFeatures: "layering"
EOF
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
spec:
  accessModes:
  - ${mode}
  resources:
    requests:
      storage: 25Gi
  storageClassName: ${scname}
EOF
}
cat<<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  volumes:
  - name: example-storage
    persistentVolumeClaim:
      claimName: <<claim>>
  containers:
  - name: example-storage
    image: <<registry:port>>/library/nginx:1.14-alpine
    ports:
    - containerPort: 80
    volumeMounts:
    - mountPath: /usr/share/nginx/html
      name: example-storage
# kubectl exec -it test-pod /bin/sh
# cd /usr/share/nginx/html
spec:
  containers:
  - name: example-storage
    image: <<registry:port>>/library/busybox:1.31.1
    imagePullPolicy: IfNotPresent
    command: ['sh', '-c']
    args: ['echo "The host is $(hostname)" >> /dir/data; sleep 3600']
    volumeMounts:
    - name: nfsdata
      mountPath: /dir
  volumes:
  - name: nfsdata
    persistentVolumeClaim:
      claimName: <<claim>>
EOF
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
    local nfs_server="" nfs_path="" nfs_readonly=""
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
            --nfs-readonly)   shift; nfs_readonly=1;;
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
            [ -z "${store_node}" ]  && usage "local sc need store_node"
            ssh_func "${user}@${master}" "${port}" sc_local "${name}" "${store_node}"
            ssh_func "${user}@${master}" "${port}" init_pvc "pvc-${name}" "${name}" "ReadWriteOnce"
            ;;
        nfs)
            [ -z "${nfs_server}" ] || [ -z "${nfs_path}" ] || [ -z "${nfs_readonly}" ] && usage "nfs sc need server/path"
            ssh_func "${user}@${master}" "${port}" sc_nfs "${name}" "${nfs_server}" "${nfs_path}" "${nfs_readonly}"
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

