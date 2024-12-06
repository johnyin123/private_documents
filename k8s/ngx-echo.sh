#!/usr/bin/env bash

NAMESPACE=default
cat <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: echo-conf
  namespace: ${NAMESPACE}
data:
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
  name: echo-application
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: echo-app
  replicas: 1
  template:
    metadata:
      labels:
        app: echo-app
    spec:
      # kubectl logs <app> -c init-mydb
      containers:
        - name: echo-app
          image: registry.local/nginx:bookworm
          # imagePullPolicy: IfNotPresent|Always|Never
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
      initContainers:
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
      volumes:
        - name: workdir
          emptyDir: {}
        - name: nginx-conf
          configMap:
            name: echo-conf
---
kind: Service
apiVersion: v1
metadata:
  name: echo-service
spec:
  type: LoadBalancer
  selector:
    app: echo-app
  ports:
    - name: http
      protocol: TCP
      targetPort: 8080
      port: 8080
EOF
