cat <<EOF
# When re-deploying a Kubernetes cluster, how can I keep the client certificates valid?
You can keep all certs in a different directory than the default directory /etc/kubernetes/pki.You do this before running kubeadm init.Now while running kubeadm init specify that directory by the --cert-dir flag or the certificatesDir field of kubeadm’s ClusterConfiguration.
Alternative option would be to skip the cert and config generation by specifying --skip-phases=certs,kubeconfig in kubeadm init.
At some point the certs will expire and you can then renew them kubeadm alpha certs renew
https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/

What about the certificates in the .conf files, e.g. admin.conf? Don’t they need to be restored as well? – 
Torsten Bronger
.conf files does not need to change unless the ca cert was regenerated...so if you follow one of the approaches then clients using the conf files will still continue to work –
All /etc/kubernetes/*.conf files (YAML) contain client keys and certificates. So additionall to pki/ we should keep those as well? –
yes you should keep them or skip that phase as well –
EOF


# call pre_conf_k8s_host first 
cat << EOF > /usr/lib/systemd/system/kubelet.service.d/20-etcd-service-manager.conf
[Service]
ExecStart=
ExecStart=/usr/bin/kubelet --address=127.0.0.1 --pod-manifest-path=/etc/kubernetes/manifests --cgroup-driver=systemd --runtime-request-timeout=15m --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock
Restart=alway
EOF

systemctl daemon-reload
systemctl restart kubelet

#---------------------------------------------
# S3-6. Creating kubeadm config (all nodes)
#---------------------------------------------
cat <<'EOF_SH' > kubeadm_setup.sh
#!/usr/bin/env bash
HOSTS=("192.168.168.150" "192.168.168.151")
NAMES=("node1" "node2")

echo "Generating ETCD CA" && kubeadm init phase certs etcd-ca
for i in "${!HOSTS[@]}"; do
    HOST=${HOSTS[$i]}
    NAME=${NAMES[$i]}
    mkdir -p ${HOST}
    cat << EOF > ${HOST}/kubeadmcfg.yaml
---
apiVersion: "kubeadm.k8s.io/v1beta3"
kind: InitConfiguration
nodeRegistration:
 name: ${NAME}
localAPIEndpoint:
 advertiseAddress: ${HOST}
---
apiVersion: "kubeadm.k8s.io/v1beta3"
kind: ClusterConfiguration
imageRepository: registry.local/google_containers
kubernetesVersion: 1.27.3
etcd:
 local:
     serverCertSANs:
     - "${HOST}"
     peerCertSANs:
     - "${HOST}"
     extraArgs:
         initial-cluster: ${NAMES[0]}=https://${HOSTS[0]}:2380,${NAMES[1]}=https://${HOSTS[1]}:2380
         initial-cluster-state: new
         name: ${NAME}
         listen-peer-urls: https://${HOST}:2380
         listen-client-urls: https://${HOST}:2379
         advertise-client-urls: https://${HOST}:2379
         initial-advertise-peer-urls: https://${HOST}:2380
EOF
    kubeadm init phase certs etcd-server             --config=${HOST}/kubeadmcfg.yaml
    kubeadm init phase certs etcd-peer               --config=${HOST}/kubeadmcfg.yaml
    kubeadm init phase certs etcd-healthcheck-client --config=${HOST}/kubeadmcfg.yaml
    kubeadm init phase certs apiserver-etcd-client   --config=${HOST}/kubeadmcfg.yaml
    cp -R /etc/kubernetes/pki ${HOST}/
    find /etc/kubernetes/pki -not -name ca.crt -not -name ca.key -type f -delete
done
EOF_SH
# S3-9. copy to all other hosts (etcd01)
# rsync -avP pki/* /etc/kubernetes/pki/
# S3-11. Creating static pod manifest (etcd01/02/03)
[etcd01]# kubeadm init phase etcd local --config=kubeadmcfg.yaml
[etcd02]# kubeadm init phase etcd local --config=kubeadmcfg.yaml
[etcd03]# kubeadm init phase etcd local --config=kubeadmcfg.yaml
# S3-13. Verify etcd cluster
crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a
crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock exec <containerid> etcdctl \
--cert /etc/kubernetes/pki/etcd/peer.crt \
--key /etc/kubernetes/pki/etcd/peer.key \
--cacert /etc/kubernetes/pki/etcd/ca.crt \
--endpoints https://192.168.168.150:2379 endpoint health

https://10.107.88.15:2379 is healthy: successfully committed proposal: took = 10.08693ms
https://10.107.88.16:2379 is healthy: successfully committed proposal: took = 10.912799ms
https://10.107.88.17:2379 is healthy: successfully committed proposal: took = 10.461484ms
