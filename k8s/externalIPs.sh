echo "test app: externip-test-app.yaml" && cat <<EOF | kubectl apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: externip-test-app
  labels:
    app: externip-test
spec:
  containers:
    - name: externip-test-app
      image: registry.local/hashicorp/http-echo
      args:
        - "-text=externip-test"
---
kind: Service
apiVersion: v1
metadata:
  name: externip-test-service
spec:
  type: ClusterIP
  selector:
    app: externip-test
  ports:
    - name: http
      protocol: TCP
      port: 5678
  externalIPs: 
    - 172.16.0.155
EOF
