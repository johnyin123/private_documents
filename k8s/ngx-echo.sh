#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("10f3a6b[2024-12-20T10:51:00+08:00]:ngx-echo.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
            DNS=1 gen hostAliases demo
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

indent() {
    local input=${1}
    echo
    sed "s/^/${input}/g"
}

limit() {
    cat <<EOF
# # 1000m=1 core cpu
resources:
  limits:
    cpu: 1000m
    memory: 1000Mi
  requests:
    cpu: 500m
    memory: 200Mi
EOF
}

liveness() {
    cat <<EOF
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15
  # Check the probe every 10 seconds
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /info
    port: 8080
  # Wait this many seconds before starting the probe
  initialDelaySeconds: 5
  periodSeconds: 5
EOF
}
security() {
    cat <<EOF
# kubectl explain pod.spec.securityContext
# kubectl explain pod.spec.containers.securityContext
securityContext:
  privileged: true
  # # hardcode user/group if not set in Dockerfile
  # # hardcode non-root. Dockerfile set USER 1000
  # runAsUser: 1000
  # runAsGroup: 1000
  # runAsNonRoot: true
EOF
}
host_alias() {
    cat <<EOF
# # in container host/dns set
hostAliases:
  - ip: "192.168.168.250"
    hostnames:
      - "srv250"
# dnsConfig:
#   nameservers:
#     - 8.8.8.8
#   searches:
#     - search.prefix
EOF
}

volumes() {
    local app_name=${1}
    cat<<EOF
# # kubectl explain pod.spec.volumes
volumes:
  # - name: output
  #   persistentVolumeClaim:
  #     claimName: output-pvc
  - name: datadir
    emptyDir: {}
  - name: nginx-conf
    configMap:
      name: ${app_name}-conf
      defaultMode: 0644
  - name: shm
    hostPath:
      path: /dev/shm
      type: Directory
  # # persistentvolume/create_pv.sh
  # - name: test-vol
  #   rbd:
  #     monitors:
  #       - 172.16.16.2:6789
  #     fsType: xfs
  #     readOnly: false
  #     pool: k8s
  #     image: rbd.img
  #     user: k8s
  #     secretRef:
  #       name: rbd-2024-12-k8s-secret
EOF
}

volume_mounts() {
cat <<EOF
volumeMounts:
  # - name: output
  #   mountPath: /output
  # # config file
  - name: nginx-conf
    mountPath: /etc/nginx/http-enabled/echo.conf
    subPath: echo.conf
    readOnly: true
  # # directory
  - name: datadir
    mountPath: /usr/share/nginx/html
  - name: shm
    mountPath: /dev/shm
EOF
}

env() {
    local app_name=${1}
    cat <<EOF
env:
  - name: ENABLE_SSH
    value: "true"
  # # env from metadata
  - name: POD_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  # # env from configmap key
  - name: DATABASE
    valueFrom:
      configMapKeyRef:
        name: ${app_name}-conf
        key: database
EOF
}

container() {
    local app_name=${1}
    local image=${2}
    local pull_policy=${3:-IfNotPresent}
    local cmds=""
    [ -t 0 ] || cmds=$(cat)
    cat <<EOF
- name: ${app_name}
  image: ${image}
  # IfNotPresent|Always|Never
  imagePullPolicy: ${pull_policy}$( \
        ( \
            [ -z "${SECURITY}" ] || security
            [ -z "${LIVE}" ] || liveness
            [ -z "${LIMIT}" ] || limit
            [ -z "${VOL}" ] || volume_mounts
            [ -z "${ENV}" ] || env "${app_name}"
            [ -z "${cmds}" ] || cat<<EOCMD
${cmds}
EOCMD
        ) | indent '  ' \
    )
EOF
}

configmap() {
    local app_name=${1}
    local namespace=${2}
    local data=""
    [ -t 0 ] || data=$(cat)
    cat <<EOF
---
# # kubectl create configmap binconfig --from-file=<binary file>
# # kubectl logs <app> -c init-mydb
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${app_name}-conf
  namespace: ${namespace}
data:$( \
        ( \
        [ -z "${data}" ] || cat<<EOCMD
${data}
EOCMD
        ) | indent '  ' \
      )
EOF
}

echo_app_deployment() {
    local app_name=${1}
    local namespace=${2}
    local replicas=${3:-1}
    configmap "${app_name}" "${namespace}" <<'EOF'
database: "mydatabase"
echo.conf: |
   server {
       listen *:8080 default_server reuseport;
       server_name _;
       set $cache_bypass 1;
       access_log off;
       location =/healthz { access_log off; default_type text/html; return 200 "$time_iso8601 $hostname alive.\n"; }
       location /info { return 200 "\$time_iso8601 Hello from $hostname. You connected from $remote_addr:$remote_port to $server_addr:$server_port\n"; }
       location / { keepalive_timeout 0; return 444; }
   }
EOF
    cat <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${app_name}
  namespace: ${namespace}
spec:
  selector:
    matchLabels:
      app: ${app_name}
  replicas: ${replicas}
  template:
    metadata:
      labels:
        app: ${app_name}
    spec:$( (volumes "${app_name}"; [ -z "${DNS}" ] || host_alias;) | indent '      ')
      containers:$( \
        LIVE=1 LIMIT=1 ENV=1 VOL=1 SECURITY= container "${app_name}" "registry.local/nginx:bookworm" "Always" <<EOCMD | indent '        '
command: ["/bin/sh", "-c"]
args:
  - |
    sed -i "/worker_processes/d" /etc/nginx/nginx.conf
    exec /usr/sbin/nginx -g "daemon off;worker_processes 1;"
EOCMD
        )
      initContainers:$( \
          ( \
          LIVE= LIMIT= ENV= VOL= SECURITY=1 container "sysctl" "registry.local/nginx:bookworm" <<EOCMD
command:
  - /bin/sh
  - -c
args:
  - |
    echo "hello sysctl"
    sysctl -w net.ipv4.ip_local_port_range='1024 65531'
EOCMD
          LIVE= LIMIT= ENV= VOL=1 SECURITY= container "initdb" "registry.local/nginx:bookworm" <<EOCMD
command: ["/bin/sh", "-c"]
args:
  - |
    echo "hello initdb"
    echo "init container" > /usr/share/nginx/html/index.html
EOCMD
          ) | indent '        ' \
        )
EOF
    service "${app_name}" "${namespace}" << EOF
ports:
  - name: http
    protocol: TCP
    targetPort: 8080
    port: 80
EOF
}

service() {
    local app_name=${1}
    local namespace=${2:-default}
    local ports=""
    [ -t 0 ] || ports=$(cat)
    cat <<EOF
---
kind: Service
apiVersion: v1
metadata:
  name: ${app_name}-service
  # # Service always in default namespace
  namespace: ${namespace}
spec:
  type: NodePort
  selector:
    app: ${app_name}$( \
        ( \
        [ -z "${ports}" ] || cat<<EOCMD
${ports}
EOCMD
        ) | indent '  ' \
    )
EOF
}
############################################################
nsenter_pod() {
    local app_name=${1:-util-linux}
    local namespace=${2:-default}
    cat <<EOF
---
############################################################
# kubectl exec ${app_name} -- nsenter --mount=/proc/1/ns/mnt -- bash -c 'ip a;cat /etc/hostname'
apiVersion: v1
kind: Pod
metadata:
  name: ${app_name}
  namespace: ${namespace}
spec:
  hostPID: true
  containers:$( \
    LIVE= LIMIT= ENV= VOL= SECURITY=1 CMD= container "nsenter" "registry.local/debian:bookworm" << EOCMD | indent '    '
command: ["/usr/bin/busybox", "sleep", "infinity"]
EOCMD
    )
EOF
}
main() {
    namespace=default
    app_name=echo-app
    replicas=1

    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
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
    echo_app_deployment "${app_name}" "${namespace}" 1
    nsenter_pod
    log "kubectl api-versions"
    log "kubectl api-resources"
    log "kubectl explain --api-version=apps/v1 replicaset"
    log "kubectl explain deployment.metadata"
    return 0
}
main "$@"
