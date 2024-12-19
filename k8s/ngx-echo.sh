#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

DNS=${DNS:-}
NAMESPACE=default
APP_NAME=echo-app
REPLICAS=1
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
    cpu: 200m
    memory: 200Mi
  requests:
    cpu: 100m
    memory: 100Mi
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
    cat<<EOF
volumes:
  # - name: output
  #   persistentVolumeClaim:
  #     claimName: output-pvc
  - name: datadir
    emptyDir: {}
  - name: nginx-conf
    configMap:
      name: ${APP_NAME}-conf
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
EOF
}

env() {
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
        name: ${APP_NAME}-conf
        key: database
EOF
}

container() {
    local name=${1}
    local image=${2}
    local pull_policy=${3:-IfNotPresent}
    cat <<EOF
- name: ${name}
  image: ${image}
  # IfNotPresent|Always|Never
  imagePullPolicy: ${pull_policy}$( \
        ( \
            [ -z "${SECURITY}" ] || security
            [ -z "${LIVE}" ] || liveness
            [ -z "${LIMIT}" ] || limit
            [ -z "${VOL}" ] || volume_mounts
            [ -z "${ENV}" ] || env
            [ -z "${CMD}" ] || {
                cat <<EO_CMD
# command: ["/bin/sh", "-c"]
command:
  - /bin/sh
  - -c
args:
  - |
    echo "hello ${name}"
EO_CMD
                [ -z "${VOL}" ] || echo '    echo "init container" > /usr/share/nginx/html/index.html'
                [ -z "${SECURITY}" ] || echo "    sysctl -w net.ipv4.ip_local_port_range='1024 65531'"
            }
        ) | indent '  ' \
    )
EOF
}

cat <<EOF
---
# # kubectl create configmap binconfig --from-file=<binary file>
# # kubectl logs <app> -c init-mydb
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP_NAME}-conf
  namespace: ${NAMESPACE}
data:
  database: "mydatabase"
  echo.conf: |
     server {
         listen *:8080 default_server reuseport;
         server_name _;
         set \$cache_bypass 1;
         access_log off;
         location =/healthz { access_log off; default_type text/html; return 200 "\$time_iso8601 \$hostname alive.\n"; }
         location /info { return 200 "\$time_iso8601 Hello from \$hostname. You connected from \$remote_addr:\$remote_port to \$server_addr:\$server_port\\n"; }
         location / { keepalive_timeout 0; return 444; }
     }
EOF
cat <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  replicas: ${REPLICAS}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:$( (volumes; [ -z "${DNS}" ] || host_alias;) | indent '      ')
      containers:$( \
        LIVE=1 LIMIT=1 ENV=1 VOL=1 SECURITY= CMD= container "${APP_NAME}" "registry.local/nginx:bookworm" "Always" \
        | indent '        ' \
        )
      initContainers:$( \
          ( \
          LIVE= LIMIT= ENV= VOL= SECURITY=1 CMD=1 container "sysctl" "registry.local/nginx:bookworm"
          LIVE= LIMIT= ENV= VOL=1 SECURITY= CMD=1 container "initdb" "registry.local/nginx:bookworm"
          ) | indent '        ' \
        )
EOF
cat <<EOF
---
kind: Service
apiVersion: v1
metadata:
  name: ${APP_NAME}-service
  # # Service always in default namespace
  # namespace: ${NAMESPACE}
spec:
  type: LoadBalancer
  selector:
    app: ${APP_NAME}
  ports:
    - name: http
      protocol: TCP
      targetPort: 8080
      port: 80
EOF
