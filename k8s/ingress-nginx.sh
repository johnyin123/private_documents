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
      image: registry.local/hashicorp/http-echo
      args:
        - "-text=apple"
---
kind: Service
apiVersion: v1
metadata:
  name: apple-service
spec:
  type: ClusterIP
  selector:
    app: apple
  ports:
    - name: http
      protocol: TCP
      port: 5678
EOF

echo "ingress: ingress.yaml" && cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  # namespace: dev
spec:
  ingressClassName: nginx
  rules:
  - host: apple.example
    http:
      paths:
      - path: /apple
        pathType: Prefix
        backend:
          service:
            name: apple-service
            port:
              number: 5678
EOF
kubectl get ingress
kubectl get ingress example-ingress
kubectl describe ingress example-ingress
curl -kL http://localhost/apple
