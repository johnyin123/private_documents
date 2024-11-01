# # https://github.com/kubernetes/ingress-nginx/deploy/static/provider/cloud/deploy.yaml
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0-beta.0/deploy/static/provider/cloud/deploy.yaml
# kubectl apply -f ingress-nginx-1.6.3.yaml
# cat ingress-nginx-1.6.3.yaml | sed "s/image: registry.k8s.io/image: registry.local/g" | kubectl apply -f -
kubectl get pods --namespace=ingress-nginx
# # wait pod up, running, and ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo "test app: apple-app.yaml" && cat <<EOF | kubectl apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: apple-app
  labels:
    app: apple
spec:
  containers:
    - name: apple-app
      image: hashicorp/http-echo
      args:
        - "-text=apple"
---
kind: Service
apiVersion: v1
metadata:
  name: apple-service
spec:
  selector:
    app: apple
  ports:
    - port: 5678
EOF

echo "ingress: ingress.yaml" && cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - http:
      paths:
        - path: /apple
          backend:
            serviceName: apple-service
            servicePort: 5678
        # - path: /banana
        #   backend:
        #     serviceName: banana-service
        #     servicePort: 5678
EOF
curl -kL http://localhost/apple
