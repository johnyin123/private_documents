#!/usr/bin/env bash

cat <<'EOF'
# # modify etcd/apiserver/scheduler/controller-manager
/etc/kubernetes/manifests/etcd.yaml
/etc/kubernetes/manifests/kube-apiserver.yaml
/etc/kubernetes/manifests/kube-scheduler.yaml
/etc/kubernetes/manifests/kube-controller-manager.yaml
EOF
MASTER_IPS="172.16.0.150 172.16.0.151 172.16.0.152"
WORKER_IPS="172.16.0.153 172.16.0.154"
for i in ${MASTER_IPS} ${WORKER_IPS}; do
    cat <<EOF > ${i}.sh
#!/bin/bash -x
SERVER=\$(kubectl config --kubeconfig=/etc/kubernetes/kubelet.conf view -o jsonpath='{.clusters[0].cluster.server}' | sed -E 's|https://(.*):6(0)?443|\1|')
NAME=\$(kubectl config view --kubeconfig=/etc/kubernetes/kubelet.conf -o jsonpath='{.clusters[0].name}')
sed -i.bak --quiet -E -e "/\s(\${SERVER})\s*\\$/!p" -e "\\\$a${i} \${SERVER}" /etc/hosts
kubectl config --kubeconfig=/etc/kubernetes/kubelet.conf set-cluster \${NAME} --server=https://\${SERVER}:60443
[ -f "\${HOME}/.kube/config" ] && sed -i "s|server:\s*https:.*|server: https://\${SERVER}:60443|" \${HOME}/.kube/config
[ -f "/etc/kubernetes/admin.conf" ] && sed -i "s|server:\s*https:.*|server: https://\${SERVER}:60443|" /etc/kubernetes/admin.conf
EOF
done
: <<EOF
allow 60443 can access outside k8s cluster.
cat <<EORULE | kubectl apply -f -
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: allow-60443-nodeports
spec:
  applyOnForward: true
  preDNAT: true
  ingress:
  - action: Allow
    destination:
      ports:
      - 60443
    protocol: TCP
    source:
      nets:
      - 0.0.0.0/0
EORULE
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: open60443
spec:
  podSelector:
      matchLabels:
        role: client
  policyTypes:
    - Ingress
  ingress:
    - from:
      - ipBlock:
          cidr: 0.0.0.0/0
      ports:
        - port: 60443
EOF
echo 'can use nginx, k8s_api.stream for this'

cat <<EOF > etc.kubernetes.api.conf
upstream kubernetes {
$(for i in ${MASTER_IPS}; do
echo "    server $i:6443 fail_timeout=1s;"
done)
}
server {
    listen 60443;
    access_log off;
    proxy_pass kubernetes;
}
EOF
cat <<EOF > api-lb.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: kube-system
spec:
  hostNetwork: true
  containers:
  - name: nginx
    image: registry.local/nginx:bookworm
    volumeMounts:
    - mountPath: /etc/nginx/stream-enabled/api.conf
      name: nginx-conf
      readOnly: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/api.conf
      type: FileOrCreate
    name: nginx-conf
EOF
