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
CIDRS=172.16.0.0/21
kubectl -n kube-system get daemonset kube-proxy -o yaml | \
  sed "s|--config=/var/lib/kube-proxy/config.conf|--config=/var/lib/kube-proxy/config.conf\n        - --ipvs-exclude-cidrs=${CIDRS}|g" | \
  kubectl apply -f -
EOF
# init_keepalived 9003 172.16.0.152 172.16.0.150 172.16.0.151 172.16.0.152 >152
MASTER_IPS="172.16.0.150 172.16.0.151 172.16.0.152"
for i in ${MASTER_IPS}; do
    init_keepalived 9999 ${i} ${MASTER_IPS} > ${i}.conf
    echo "on $i: modify ~/.kube/config(server: https://myserver:6443 --> https://myserver:60443), add '$i myserver' /etc/hosts"
done
