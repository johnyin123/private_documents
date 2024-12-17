#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

NAMESPACE=default
APP_NAME=echo-app
REPLICAS=1
indent() {
    local input=${1}
    echo
    sed "s/^/${input}/g"
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
securityContext:
  privileged: true
  # # hardcode user to non-root if not set in Dockerfile
  # runAsUser: 1000
  # # hardcode group to non-root if not set in Dockerfile
  # runAsGroup: 1000
  # # hardcode to non-root. Redundant to above if Dockerfile is set USER 1000
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
cat <<EOF
---
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
    spec:
      # kubectl logs <app> -c init-mydb$([ -z "${DNS:-}" ] || host_alias | indent '      ')
      containers:
        - name: ${APP_NAME}
          image: registry.local/nginx:bookworm
          # |Always|Never
          imagePullPolicy: IfNotPresent$(liveness | indent '          ')
          # volumeMounts:
          #   - name: output
          #     mountPath: /output
          volumeMounts:
          # # config file
          - name: nginx-conf
            mountPath: /etc/nginx/http-enabled/echo.conf
            subPath: echo.conf
            readOnly: true
          # # directory
          - name: datadir
            mountPath: /usr/share/nginx/html
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
      initContainers:
        # # side cars
        - name: sysctl$(security | indent '          ')
          image: registry.local/nginx:bookworm
          command:
            - /bin/bash
            - -c
          args:
            - "sysctl -w net.core.somaxconn=65535; sysctl -w net.ipv4.ip_local_port_range='1024 65531'"
        - name: init-mydb
          image: registry.local/nginx:bookworm
          command: ["sh", "-c"]
          args:
            - |
              echo "Command 1"
              echo "init container" > /work-dir/index.html
          volumeMounts:
          - name: datadir
            mountPath: "/work-dir"
      # # pvc
      # volumes:
      #   - name: output
      #     persistentVolumeClaim:
      #       claimName: output-pvc
      volumes:
        - name: datadir
          emptyDir: {}
        - name: nginx-conf
          configMap:
            name: ${APP_NAME}-conf
---
kind: Service
apiVersion: v1
metadata:
  name: echo-service
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
