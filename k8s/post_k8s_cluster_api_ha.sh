#!/usr/bin/env bash

init_keepalived() {
    local id=${1}
    local vip=${2}
    shift 2
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
    persistence_timeout 360
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
CIDRS=172.16.0.0/21 # # k8s node host cidrs
kubectl -n kube-system get daemonset kube-proxy -o yaml | \
  sed "s|--config=/var/lib/kube-proxy/config.conf|--config=/var/lib/kube-proxy/config.conf\n        - --ipvs-exclude-cidrs=${CIDRS}|g" | \
  kubectl apply -f -
EOF
# init_keepalived 9003 172.16.0.152 172.16.0.150 172.16.0.151 172.16.0.152 >152
MASTER_IPS="172.16.0.150 172.16.0.151 172.16.0.152"
WORKER_IPS="172.16.0.153 172.16.0.154"
for i in ${MASTER_IPS} ${WORKER_IPS}; do
    init_keepalived 9999 ${i} ${MASTER_IPS} > ${i}.keepalived.conf
    cat <<EOF > ${i}.sh
#!/bin/bash -x
SERVER=\$(kubectl config --kubeconfig=/etc/kubernetes/kubelet.conf view -o jsonpath='{.clusters[0].cluster.server}' | sed -E 's|https://(.*):6(0)?443|\1|')
NAME=\$(kubectl config view --kubeconfig=/etc/kubernetes/kubelet.conf -o jsonpath='{.clusters[0].name}')
sed -i.bak --quiet -E -e "/\s(\${SERVER})\s*\\$/!p" -e "\\\$a${i} \${SERVER}" /etc/hosts
kubectl config --kubeconfig=/etc/kubernetes/kubelet.conf set-cluster \${NAME} --server=https://\${SERVER}:60443
[ -f "\${HOME}/.kube/config" ] && sed -i "s|server:\s*https:.*|server: https://\${SERVER}:60443|" \${HOME}/.kube/config
EOF
done
