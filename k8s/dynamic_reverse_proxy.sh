NAMESPACE=
# kubectl create configmap confnginx --from-file=./nginx.conf -n namespace

cat <<CONFIGMAP
apiVersion: v1
kind: ConfigMap
metadata:
  name: confnginx
data:
  nginx.conf: |
    user nginx;
    worker_processes 1;
    error_log /var/log/nginx/error.log warn;
    pid /var/run/nginx.pid;
    events {
        worker_connections 1024;
    }
    http {
      include /etc/nginx/mime.types;
      default_type application/octet-stream;
      log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
      access_log /var/log/nginx/access.log main;
      sendfile on;
      keepalive_timeout 65;
      server {
        listen 80;
        server_name ~^(?<subdomain>.*?)\.;
        resolver kube-dns.kube-system.svc.cluster.local valid=5s;
        location /healthz {
          return 200;
        }
        location / {
          proxy_set_header Upgrade \$http_upgrade;
          proxy_set_header Connection "Upgrade";
          proxy_pass http://\$subdomain.${NAMESPACE}.svc.cluster.local;
          proxy_set_header Host \$host;
          proxy_http_version 1.1;
        }
      }
    }
CONFIGMAP

cat <<DEPLOYMENT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
          - containerPort: 80
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
      volumes:
        - name: nginx-config
          configMap:
            name: confnginx
DEPLOYMENT

cat <<SERVICE
kind: Service
apiVersion: v1
metadata:
  name: nginx-custom
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    name: nginx
SERVICE

cat <<INGRESS
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: ingress-nginx-custom
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: '*.mydomain.com'
    http:
      paths:
      - path: /
        backend:
          serviceName: nginx-custom
          servicePort: 80
INGRESS
