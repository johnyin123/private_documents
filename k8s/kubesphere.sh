#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("9468d8b[2024-12-06T12:36:33+08:00]:kubesphere.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
KS_INSTALLER_YML="https://github.com/kubesphere/ks-installer/releases/download/v3.3.2/kubesphere-installer.yaml"
L_KS_INSTALLER_YML=kubesphere-installer.yaml
R_KS_INSTALLER_YML="$(mktemp)"

CLUSTER_CONF_YML="https://github.com/kubesphere/ks-installer/releases/download/v3.3.2/cluster-configuration.yaml"
L_CLUSTER_CONF_YML=cluster-configuration.yaml
R_CLUSTER_CONF_YML="$(mktemp)"

pre_check() {
    info_msg "cephfs storage\n"
    cat<<'EOF'
action=${1:-apply}
cat <<EO_YML | kubectl ${action} -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
provisioner: kubernetes.io/cephfs
metadata:
  name: sc-2024-12-cephfs
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
EO_YML
for namespace in kubesphere-system kubesphere-monitoring-system kubesphere-devops-system kubesphere-logging-system; do
	cat <<EO_YML | kubectl ${action} -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
---
apiVersion: v1
kind: Secret
metadata:
  name: cephfs-2024-12-k8s-secret
  namespace: ${namespace}
data:
  key: QVFDaUYxRm5obUVwTEJBQTE4ZTRFNXc1VzJaSlFoNElTcEthZmc9PQ==
EO_YML
done
for seq in $(seq -w 1 30); do
cat <<EO_YML | kubectl ${action} -f -
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-2024-12-cephfs-${seq}
spec:
  capacity:
    storage: 30G
  accessModes:
    - ReadWriteOnce
    - ReadWriteMany
    - ReadOnlyMany
  volumeMode: Filesystem
  persistentVolumeReclaimPolicy: Delete
  storageClassName: sc-2024-12-cephfs
  cephfs:
    monitors:
    - 172.16.16.2:6789
    - 172.16.16.3:6789
    - 172.16.16.4:6789
    - 172.16.16.7:6789
    - 172.16.16.8:6789
    user: k8s
    path: /k8s/${seq}
    secretRef:
      name: cephfs-2024-12-k8s-secret
    readOnly: false
EO_YML
done
EOF
    info_msg "iscsi storage\n"
    cat<<'EOF'
action=${1:-apply}
cat <<EO_YML | kubectl ${action} -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
provisioner: kubernetes.io/iscsi
metadata:
  name: sc-2024-12-iscsi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
EO_YML
for namespace in kubesphere-system kubesphere-monitoring-system kubesphere-devops-system kubesphere-logging-system; do
cat <<EO_YML | kubectl ${action} -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
---
apiVersion: v1
kind: Secret
metadata:
  name: iscsi-2024-12-testuser-secret
  namespace: ${namespace}
type: kubernetes.io/iscsi-chap
data:
  node.session.auth.username: dGVzdHVzZXI=
  node.session.auth.password: cGFzc3dvcmQxMjM=
EO_YML
# # pv list
#  1 kubesphere-devops-system/devops-jenkins
#  2 kubesphere-logging-system/data-elasticsearch-logging-data-0
#  3 kubesphere-logging-system/data-elasticsearch-logging-data-1
#  4 kubesphere-logging-system/data-elasticsearch-logging-data-2
#  5 kubesphere-logging-system/data-elasticsearch-logging-discovery-0
#  6 kubesphere-logging-system/data-elasticsearch-logging-discovery-1
#  7 kubesphere-logging-system/data-elasticsearch-logging-discovery-2
#  8 kubesphere-monitoring-system/prometheus-k8s-db-prometheus-k8s-0
#  9 kubesphere-monitoring-system/prometheus-k8s-db-prometheus-k8s-1
# 10 kubesphere-system/data-redis-ha-server-0
# 11 kubesphere-system/data-redis-ha-server-1
# 12 kubesphere-system/data-redis-ha-server-2
# 13 kubesphere-system/minio
# 14 kubesphere-system/openldap-pvc-openldap-0
# 15 kubesphere-system/openldap-pvc-openldap-1
for seq in $(seq -w 1 16); do
cat <<EO_YML | kubectl ${action} -f -
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-2024-12-rbd${seq}-iscsi
spec:
  capacity:
    storage: 30G
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  persistentVolumeReclaimPolicy: Retain
  storageClassName: sc-2024-12-iscsi
  iscsi:
    targetPortal: 172.16.0.156:3260
    portals: [ '172.16.0.157:3260' ]
    iqn: iqn.2024-12.rbd${seq}.local:iscsi-01
    lun: 1
    chapAuthSession: true
    secretRef:
      name: iscsi-2024-12-testuser-secret
    readOnly: false
    fsType: xfs
EO_YML
done
EOF
    info_msg "nfs storage\n"
    cat<<'EOF'
1.need storageclass(default); in-tree sc cannot dynamic create pv. so create enough pv first
# kubectl patch storageclass sc-ks-nfs -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
cat <<EOSHELL | kubectl apply -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
provisioner: kubernetes.io/nfs
metadata:
  name: sc-ks-nfs
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
EOSHELL
for i in $(seq -w 1 16); do
cat <<EOSHELL | kubectl apply -f -
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-ks-${i}-nfs
spec:
  capacity:
    storage: 30G
  accessModes:
    - ReadWriteMany
    - ReadWriteOnce
    - ReadOnlyMany
  volumeMode: Filesystem
  persistentVolumeReclaimPolicy: Retain
  storageClassName: sc-ks-nfs
  nfs:
    path: "/nfs_share/${i}"
    server: "172.16.0.156"
    readOnly: false
EOSHELL
done
    nfs must has directory: /nfs_share/<i>
2. todo
EOF
}

init_kubesphere() {
    local ks_cluster_yaml=${1}
    local ks_installer_yaml=${2}
    kubectl apply -f "${ks_installer_yaml}"
    kubectl apply -f "${ks_cluster_yaml}"
    # rm -f "${ks_cluster_yaml}" "${ks_installer_yaml}"
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
usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
        env:
            SUDO=   default undefine
        -m|--master      *  <ip>    master ipaddr
        --insec_registry *  <str>   insecurity registry(http/no auth)
        --installer      *  <str>   ks-installer image image
                                    exam: registry.local/kubesphere/ks-installer:v3.2.1
        --alerting                  ks alerting
        --auditing                  ks auditing
        --logging                   ks logging
        --devops                    ks devops
        --events                    ks events
        -U|--user           <user>  master ssh user, default root
        -P|--port           <int>   master ssh port, default 60022
        --sshpass           <str>   master ssh password, default use keyauth
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        prepare sotrageclass(default)
        prepare image: https://github.com/kubesphere/ks-installer/releases/download/v3.2.1/images-list.txt
        exam:
            ${SCRIPTNAME} -m 172.16.0.150 --insec_registry registry.local --installer registry.local/kubesphere/ks-installer:v3.3.2
EOF
)"; echo -e "${usage_doc}"
    exit 1
}
main() {
    local master="" insec_registry="" installer=""
    local alerting="false" auditing="false" logging="false" devops="false" events="false"
    local user=root port=60022
    local opt_short="m:U:P:"
    local opt_long="master:,insec_registry:,installer:,alerting,auditing,logging,devops,events,password:,user:,port:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m | --master)    shift; master=${1}; shift;;
            --insec_registry) shift; insec_registry=${1}; shift;;
            --installer)      shift; installer=${1}; shift;;
            --alerting)       shift; alerting="true";;
            --auditing)       shift; auditing="true";;
            --logging)        shift; logging="true";;
            --devops)         shift; devops="true";;
            --events)         shift; events="true";;
            -U | --user)      shift; user=${1}; shift;;
            -P | --port)      shift; port=${1}; shift;;
            --password)       shift; set_sshpass "${1}"; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; pre_check; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${insec_registry}" ] || [ -z "${installer}" ] || [ -z "${master}" ] && usage "master/insec_registry/ks_installer must input"
    file_exists "${L_KS_INSTALLER_YML}" && file_exists "${L_CLUSTER_CONF_YML}" || \
        confirm "${L_KS_INSTALLER_YML}/${L_CLUSTER_CONF_YML} not exists, continue? (timeout 10,default N)?" 10 || exit_msg "BYE!\n"
    local folder=$(temp_folder)
    local modifyed_yaml="${folder}/${L_CLUSTER_CONF_YML}"
    cat "${L_CLUSTER_CONF_YML}" | yaml2json \
        | jq ".spec.local_registry=\"${insec_registry}\"" \
        |  jq '.spec.common.openldap.enabled=false' \
        |      jq '.spec.common.redis.enabled=true' \
        | jq '.spec.openpitrix.store.enabled=false' \
        |    jq '.spec.metrics_server.enabled=true' \
        |   jq ".spec.alerting.enabled=${alerting}" \
        |   jq ".spec.auditing.enabled=${auditing}" \
        |     jq ".spec.logging.enabled=${logging}" \
        |       jq ".spec.devops.enabled=${devops}" \
        |       jq ".spec.events.enabled=${events}" \
        | json2yaml > ${modifyed_yaml}
    info_msg "locale modifyed is ${modifyed_yaml}\n"
    prepare_yml "${user}" "${port}" "${master}" "${modifyed_yaml}" "${R_CLUSTER_CONF_YML}" "${CLUSTER_CONF_YML}"
    modifyed_yaml="${folder}/${L_KS_INSTALLER_YML}"
    cat "${L_KS_INSTALLER_YML}" | sed "s|image\s*:\s*.*ks-installer.*|image: ${installer}|g" > "${modifyed_yaml}"
    info_msg "locale modifyed is ${modifyed_yaml}\n"
    prepare_yml "${user}" "${port}" "${master}" "${modifyed_yaml}" "${R_KS_INSTALLER_YML}" "${KS_INSTALLER_YML}"
    vinfo_msg <<EOF
insec_registry:  ${insec_registry}
installer: ${installer}
EOF
    ssh_func "${user}@${master}" "${port}" init_kubesphere "${R_CLUSTER_CONF_YML}" "${R_KS_INSTALLER_YML}"
    cat <<EOF
安装后如何开启安装应用商店:
# kubectl -n kubesphere-system edit clusterconfiguration ks-installer
kubectl -n kubesphere-system get clusterconfiguration ks-installer -o yaml
    openpitrix:
      enabled: True
# 通过查询 ks-installer 日志或 Pod 状态验证功能组件是否安装成功。
kubectl logs -n kubesphere-system \$(kubectl get pod -n kubesphere-system -l 'app in (ks-install, ks-installer)' -o jsonpath='{.items[0].metadata.name}') -f
kubectl -n kubesphere-system rollout restart deployment.apps/ks-installer
kubectl -n kubesphere-system logs -f ks-installer-

kubectl -n kubesphere-system rollout restart deployment.apps/redis
kubectl -n kubesphere-monitoring-system delete pvc prometheus-k8s-db-prometheus-k8s-1 prometheus-k8s-db-prometheus-k8s-0

# # fix arm64 default-http-backend pod error
kubectl -n kubesphere-controls-system edit deployment.apps/default-http-backend
kubectl -n kubesphere-controls-system rollout restart deployment.apps/default-http-backend

kubectl rollout restart statefulset.apps/prometheus-k8s -n kubesphere-monitoring-system

kubectl get pods -A -o json | jq  -r '.items[] | select(.status.phase!="Running") | "kubectl -n " + .metadata.namespace + " describe pod " +.metadata.name + "\n" + "kubectl -n " + .metadata.namespace + " logs " +.metadata.name '  | bash -x
EOF
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
