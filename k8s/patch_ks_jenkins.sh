#!/usr/bin/env bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ngx-conf
  namespace: kubesphere-devops-system
data:
  echo.conf: |
     server {
         listen *:8888 default_server reuseport;
         server_name _;
         access_log off;
         location / { root /var/jenkins_home; }
     }
EOF
cat <<'EOF' | kubectl apply -f -
kind: Service
apiVersion: v1
metadata:
  name: jenkins-download-service
  namespace: kubesphere-devops-system
spec:
  type: LoadBalancer
  selector:
    component: devops-jenkins-master
  ports:
    - name: http
      protocol: TCP
      targetPort: 8888
      port: 88
EOF
kubectl patch -n kubesphere-devops-system deployment.apps/devops-jenkins -p '{"spec": {"template": {"spec": {"containers": [{"image": "registry.local/nginx:bookworm", "imagePullPolicy": "IfNotPresent", "name": "ngx", "volumeMounts": [{"mountPath": "/etc/nginx/http-enabled/echo.conf", "name": "ngx-conf", "readOnly": true, "subPath": "echo.conf"}, {"mountPath": "/var/jenkins_home", "name": "jenkins-home", "readOnly": true}]}], "volumes": [{"configMap": {"defaultMode": 420, "name": "ngx-conf"}, "name": "ngx-conf"}]}}}}'
