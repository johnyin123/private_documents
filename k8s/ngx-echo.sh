#!/usr/bin/env bash

NAMESPACE=default
APP_NAME=echo-app
REPLICAS=1
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
         location =/healthz { keepalive_timeout 0; access_log off; default_type text/html; return 200 "\$time_iso8601 \$hostname alive.\n"; }
         location /info { keepalive_timeout 0; return 200 "\$time_iso8601 Hello from \$hostname. You connected from \$remote_addr:\$remote_port to \$server_addr:\$server_port\\n"; }
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
      # kubectl logs <app> -c init-mydb
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
      containers:
        - name: ${APP_NAME}
          image: registry.local/nginx:bookworm
          # |Always|Never
          imagePullPolicy: IfNotPresent
          # volumeMounts:
          #   - name: output
          #     mountPath: /output
          volumeMounts:
          - name: nginx-conf
            mountPath: /etc/nginx/http-enabled/echo.conf
            subPath: echo.conf
            readOnly: true
          - name: workdir
            mountPath: /usr/share/nginx/html
          env:
            - name: ENABLE_SSH
              value: "true"
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: DATABASE
              valueFrom:
                configMapKeyRef:
                  name: ${APP_NAME}-conf
                  key: database
      initContainers:
        - name: sysctl
          securityContext:
            privileged: true
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
          - name: workdir
            mountPath: "/work-dir"
      # volumes:
      #   - name: output
      #     persistentVolumeClaim:
      #       claimName: output-pvc
      volumes:
        - name: workdir
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
