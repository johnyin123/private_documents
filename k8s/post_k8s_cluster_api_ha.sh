#!/usr/bin/env bash

init_keepalived() {
    local id=${1}
    local vip=${2}
    local worker=${3}
    shift 3
    local real_ips="${*}"
    local ip=""
cat <<EOF 
global_defs {
   router_id ${id}
}
virtual_server ${vip} 60443 {
    delay_loop 2
    lb_algo rr
    lb_kind NAT
    protocol TCP
$(for ip in ${real_ips}; do
cat<<EO_REAL
    real_server ${ip} 6443 {
        weight 1
        SSL_GET {
            url {
              path /healthz
              digest 444bcb3a3fcf8389296c49467f27e1d6
            }
            connect_timeout 1
            retry 3
        }
    }
EO_REAL
done)
}
EOF
${worker} && cat <<EOF
virtual_server ${vip} 6443 {
    delay_loop 2
    lb_algo rr
    lb_kind NAT
    protocol TCP
$(for ip in ${real_ips}; do
cat<<EO_REAL
    real_server ${ip} 6443 {
        weight 1
        SSL_GET {
            url {
              path /healthz
              digest 444bcb3a3fcf8389296c49467f27e1d6
            }
            connect_timeout 1
            retry 3
        }
    }
EO_REAL
done)
}
EOF
}
cat <<'EOF'
TODO: NEED TEST! if use service nodeport mode.
CIDRS=172.16.0.0/21 # # k8s node host cidrs
kubectl -n kube-system get daemonset kube-proxy -o yaml | \
  sed "s|--config=/var/lib/kube-proxy/config.conf|--config=/var/lib/kube-proxy/config.conf\n        - --ipvs-exclude-cidrs=${CIDRS}|g" | \
  kubectl apply -f -
# # modify etcd/apiserver/scheduler/controller-manager
/etc/kubernetes/manifests/etcd.yaml
/etc/kubernetes/manifests/kube-apiserver.yaml
/etc/kubernetes/manifests/kube-scheduler.yaml
/etc/kubernetes/manifests/kube-controller-manager.yaml
EOF
# init_keepalived 9003 172.16.0.152 false 172.16.0.150 172.16.0.151 172.16.0.152 >152
MASTER_IPS="172.16.0.150 172.16.0.151 172.16.0.152"
WORKER_IPS="172.16.0.153 172.16.0.154"
for i in ${MASTER_IPS}; do
    init_keepalived 9999 ${i} false ${MASTER_IPS} > ${i}.master.keepalived.conf
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
for i in ${WORKER_IPS}; do
    init_keepalived 9999 ${i} true ${MASTER_IPS} > ${i}.worker.keepalived.conf
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

cat <<EOF
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
