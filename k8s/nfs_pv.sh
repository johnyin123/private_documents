#!/usr/bin/env bash
echo "ALL CHECK OK, nfs pv support by k8s buildin, so noneed other csi/pods"
NFS_SRV=172.16.0.152
NFS_PATH=/nfs_share
namespace=default
cat <<EOF
nfs server: yum -y install nfs-utils && systemctl start nfs-server.service && rpcinfo -p | grep nfs
mkdir -p ${NFS_PATH} && chown -R nobody:nobody ${NFS_PATH}
echo '${NFS_PATH} 172.16.0.1/24(rw,sync,no_all_squash,root_squash)' > /etc/exports
exportfs -arv
exportfs -s
nfs client: yum -y install nfs-utils nfs4-acl-tools
EOF
echo "create NFS PersistentVolume" && cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
  namespace: ${namespace}
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: "${NFS_PATH}"
    server: "${NFS_SRV}"
    readOnly: false
EOF

echo "create NFS pvc" && cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc1
  namespace: ${namespace}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF

echo "Use NFS PVC in a pod" && cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nfs-pv-test
  namespace: ${namespace}
spec:
  containers:
  - name: nfs-pv-rw
    image: registry.local/debian:bookworm
    command:
      - "/bin/sh"
    args:
      - "-c"
      - "busybox ip a > /mnt/SUCCESS && exit 0 || exit 1"
    volumeMounts:
    - mountPath: "/mnt"
      name: test-nfs 
  restartPolicy: "Never"
  volumes:
  - name: test-nfs
    persistentVolumeClaim:
      claimName: nfs-pvc1
EOF
