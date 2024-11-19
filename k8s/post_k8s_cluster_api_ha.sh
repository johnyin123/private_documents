#!/usr/bin/env bash
API_SRV_NAME=myserver
VIP=172.16.0.155
MASTER_IPS="172.16.0.150 172.16.0.151 172.16.0.152"

cat <<'EOF'
# # modify etcd/apiserver/scheduler/controller-manager
/etc/kubernetes/manifests/etcd.yaml
/etc/kubernetes/manifests/kube-apiserver.yaml
/etc/kubernetes/manifests/kube-scheduler.yaml
/etc/kubernetes/manifests/kube-controller-manager.yaml
# # get all master ip:
kubectl get nodes --selector=node-role.kubernetes.io/master -o jsonpath='{$.items[*].status.addresses[?(@.type=="InternalIP")].address}'
EOF

cat <<EOF > api-lb.yaml
# # bad idea, sometime not work on worker node
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: kube-system
spec:
  hostNetwork: true
  securityContext:
    privileged: true
  containers:
  - name: nginx
    image: registry.local/nginx:bookworm
    volumeMounts:
    - mountPath: /etc/nginx/stream-enabled/api.conf
      name: nginx-conf
      readOnly: true
  - name: keepalived
    image: registry.local/nginx:bookworm
    securityContext:
      privileged: true
    command:
    - /bin/bash
    - -c
    - /entrypoint.sh
    volumeMounts:
    - mountPath: /etc/keepalived
      name: keepalived-cfg
      readOnly: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/api.conf
      type: FileOrCreate
    name: nginx-conf
  - hostPath:
      path: /etc/keepalived
    name: keepalived-cfg
EOF
init_keepalived() {
    local id=${1}
    local vip=${2}
    local dev=${3}
    local src=${4}
    shift 4
    local real_ips="${*}"
    local ip=""
cat <<EOF
global_defs {
    router_id ${id}
    vrrp_skip_check_adv_addr
    vrrp_garp_interval 0
    vrrp_gna_interval 0
}
vrrp_instance kube-api-vip {
    state BACKUP
    priority 100
    interface ${dev}
    virtual_router_id 60
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass passwd4kube-api-vip
    }
    unicast_src_ip ${src}
    unicast_peer {
$(for ip in ${real_ips}; do
    [ "${src}" == "${ip}" ] && continue
    cat<<EO_REAL
        ${ip}
EO_REAL
done)
    }
    virtual_ipaddress {
        ${vip}
    }
    # notify_master ""
    # notify_backup ""
    # notify_stop ""
}
EOF
}
# init_keepalived 9003 172.16.0.152 172.16.0.150 172.16.0.151 172.16.0.152 >152
for i in ${MASTER_IPS}; do
    init_keepalived 9999 ${VIP} "eth0" ${i} ${MASTER_IPS} > ${i}.conf
    echo "on $i: modify ~/.kube/config(server: https://myserver:6443 --> https://myserver:60443), add '${VIP} myserver' /etc/hosts"
done

cat <<EOF > etc.kubernetes.api.conf
upstream kube-api {
$(for i in ${MASTER_IPS}; do
echo "    server $i:6443 fail_timeout=1s;"
done)
}
server {
    listen 60443;
    access_log off;
    proxy_pass kube-api;
}
EOF
cat <<EOF
for ip in ${MASTER_IPS}; do
    ssh root@\${ip} "rm -f /etc/keepalived/* /etc/nginx/stream-enabled/*; sed -i -e '/\s*${API_SRV_NAME}/d' /etc/hosts; echo '${VIP} ${API_SRV_NAME}' >> /etc/hosts"
    scp \$ip.conf root@\${ip}:/etc/keepalived/keepalived.conf
    scp etc.kubernetes.api.conf root@\${ip}:/etc/nginx/stream-enabled/
done
# kubectl -n kube-system edit configmaps coredns -o yaml
# hosts {
#    ${VIP} ${API_SRV_NAME}
# }
# # # forward . /etc/resolv.conf
EOF
: <<EOF
# # sed -i "s/--advertise-address=/--bind-address=/g" /etc/kubernetes/manifests/kube-apiserver.yaml
# # CIDRS=172.16.0.0/21
# # kubectl -n kube-system get daemonset kube-proxy -o yaml | \
# #   sed "s|--config=/var/lib/kube-proxy/config.conf|--config=/var/lib/kube-proxy/config.conf\n        - --ipvs-exclude-cidrs=${CIDRS}|g" | \
# #   kubectl apply -f -
EOF
