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
echo "create seacret" && cat <<EOF | kubectl apply -f -
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

echo "create pvc" && cat <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: claim1
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

echo "Use the PVC in a pod" && cat <<EOF
kind: Pod
apiVersion: v1
metadata:
  name: cephfs
spec:
  containers:
  - name: cephfs-rw
    image: registry.local/debian:bookworm
    # image: registry.local/library/busybox:latest
    command:
      - "/bin/sh"
    args:
      - "-c"
      - "touch /mnt/cephfs/SUCCESS && exit 0 || exit 1"
    volumeMounts:
    - mountPath: "/mnt/cephfs"
      name: cephfs  
  restartPolicy: "Never"
  volumes:
  - name: cephfs
    persistentVolumeClaim:
      claimName: claim1
EOF
