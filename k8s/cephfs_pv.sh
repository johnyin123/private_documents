#!/usr/bin/env bash
echo "ALL CHECK OK, cephfs pv support by k8s buildin, so noneed other csi/pods"
# # yum -y install ceph-common
ceph_user=k8s
cephfs_path=/cephfs4kubernetes
# ceph fs ls
# ceph fs authorize tsdfs client.${ceph_user} /${cephfs_path} rw
# ceph auth get-key client.${ceph_user}
ceph_key=uSlE9PQ==
# # mount -t ceph 172.16.16.3:6789:/cephfs_path /mnt/ -oname=${ceph_user},secret=${ceph_key}
# # mkdir -p /mnt/${cephfs_path}
namespace=default
echo "create secret" && cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ceph-${ceph_user}-secret
  namespace: ${namespace}
data:
  key: $(echo -n ${ceph_key} | base64)
EOF

echo "create PersistentVolume" && cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: cephfs
  namespace: ${namespace}
  labels:
    pv: cephfs
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteMany
  cephfs:
    monitors:
    - 172.16.16.2:6789
    - 172.16.16.3:6789
    user: ${ceph_user}
    path: ${cephfs_path}
    secretRef:
      name: ceph-${ceph_user}-secret
    readOnly: false
EOF

echo "create pvc" && cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cephfs_pvc1
  namespace: ${namespace}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 2Gi
  selector:
    matchLabels:
      pv: cephfs
EOF

echo "Use CEPHFS PVC in a pod" && cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cephfs
  namespace: ${namespace}
spec:
  containers:
  - name: cephfs-rw
    image: registry.local/debian:bookworm
    command:
      - "/bin/sh"
    args:
      - "-c"
      - "busybox ip a > /mnt/cephfs/SUCCESS && exit 0 || exit 1"
    volumeMounts:
    - mountPath: "/mnt/cephfs"
      name: cephfs  
  restartPolicy: "Never"
  volumes:
  - name: cephfs
    persistentVolumeClaim:
      claimName: cephfs_pvc1
EOF
