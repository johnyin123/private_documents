cat <<'EOF'
FSID=$(ceph fsid)
CEPHFS_KEY=$(ceph auth get-key client.${CEPHFS_USER})
CEPHFS_NAME=$(ceph fs ls -f json | jq -r '.[0].name')
ceph config generate-minimal-conf > ceph.conf
fsname=$(ceph fs volume ls | jq -r '.[0].name')

kubectl -n cephcsi exec -it csi-cephfsplugin-provisioner-xx -c csi-cephfsplugin -- /bin/bash
EOF
#######################
REGISTRY=registry.local
NAMESPACE=cephcsi
CSI_VERSION=v3.7.2
TYPES=(rbd cephfs)
#######################
FSID=f0510d24-a438-4ad4-8ab3-5c0cc75991eb
MONS="172.16.0.156:6789,172.16.0.157:6789,172.16.0.158:6789"
#######################
CEPHFS_NAME=tsdfs
CEPHFS_USER=tsdfs-admin
CEPHFS_KEY=AQBXZ25neGTyOhAAD32SCFsOLweUQXhYqfyv0w==
#######################
RBD_POOL=k8s-pool
RBD_USER=k8s-pool-admin
RBD_KEY=AQD9aG5n9H9AChAADiTb3i1Vq1Q7kuUz6Il4pA==
#######################
kubectl create namespace ${NAMESPACE} || true
for type in ${TYPES[@]}; do
    sed -i "s/image\s*:\s*[^\/]*\//image: ${REGISTRY}\//g" ${type}-${CSI_VERSION}-csi*.yaml
    sed -i "s/namespace\s*:\s*.*/namespace: ${NAMESPACE}/g" ${type}-${CSI_VERSION}-csi*.yaml
    kubectl apply -n ${NAMESPACE} -f ${type}-${CSI_VERSION}-csi-provisioner-rbac.yaml
    kubectl apply -n ${NAMESPACE} -f ${type}-${CSI_VERSION}-csi-nodeplugin-rbac.yaml
    kubectl apply -n ${NAMESPACE} -f ${type}-${CSI_VERSION}-csi-${type}plugin-provisioner.yaml
    kubectl apply -n ${NAMESPACE} -f ${type}-${CSI_VERSION}-csi-${type}plugin.yaml
    kubectl apply -n ${NAMESPACE} -f ${type}-${CSI_VERSION}-csidriver.yaml
done

cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-config
data:
  config.json: |-
    [
      {
        "clusterID": "${FSID}",
        "monitors": [ "$(echo "${MONS}" | sed 's/,/","/g')" ],
        "cephFS": {
          "subvolumeGroup": "csi"
        }
      }
    ]
EOF
cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-encryption-kms-config
data:
  config.json: |-
    {}
EOF
cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-config
data:
  ceph.conf: |
    [global]
    auth_cluster_required = cephx
    auth_service_required = cephx
    auth_client_required = cephx
    fuse_big_writes = true
  # keyring is a required key and its value should be empty
  keyring: |
EOF

for type in ${TYPES[@]}; do
    cat <<EOF | kubectl -n "${NAMESPACE}" apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: csi-${type}-secret
stringData:
  encryptionPassphrase: test_passphrase
$([ "${type}" == "rbd" ] && { cat <<EO_ADMIN
  userID: ${RBD_USER}
  userKey: ${RBD_KEY}
EO_ADMIN
})
$([ "${type}" == "cephfs" ] && { cat <<EO_ADMIN
  # Required for dynamically provisioned volumes
  userID: ${CEPHFS_USER}
  userKey: ${CEPHFS_KEY}
  # Required for statically provisioned volumes
  adminID: ${CEPHFS_USER}
  adminKey: ${CEPHFS_KEY}
EO_ADMIN
})
EOF
done
for type in ${TYPES[@]}; do
    cat <<EOF | kubectl apply -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${type}-storage-class
provisioner: ${type}.csi.ceph.com
reclaimPolicy: Retain
allowVolumeExpansion: true
mountOptions:
  - discard
parameters:
  clusterID: ${FSID}
  csi.storage.k8s.io/provisioner-secret-name: csi-${type}-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/controller-expand-secret-name: csi-${type}-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/node-stage-secret-name: csi-${type}-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ${NAMESPACE}
  $([ "${type}" == "rbd" ] && { echo "pool: ${RBD_POOL}";echo "  imageFeatures: layering";}
    [ "${type}" == "cephfs" ] && { echo "fsName: ${CEPHFS_NAME}"; })
EOF
done
#######################
cephfs_test() {
    cat <<EOF > testpod.yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: block-rbd-pvc
spec:
  accessModes:
    # ReadWriteMany is only supported for Block PVC
    - ReadWriteOnce
  volumeMode: Block
  resources:
    requests:
      storage: 1Gi 
  storageClassName: rbd-storage-class
EOF
    cat <<EOF >> testpod.yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: filesystem-rbd-pvc
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Gi
  storageClassName: rbd-storage-class
EOF
    cat <<EOF >> testpod.yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cephfs-pvc
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 100Mi
  storageClassName: cephfs-storage-class
EOF
    cat <<EOF >> testpod.yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: ceph-csi-test
spec:
  containers:
    - name: ceph-csi-test
      image: registry.local/debian:bookworm
      imagePullPolicy: IfNotPresent
      command: ["/usr/bin/busybox", "sleep", "infinity"]
      volumeMounts:
      - name: ceph-csi
        mountPath: /mnt
      volumeDevices:
      - name: ceph-csi-block
        devicePath: /dev/xvda
  volumes:
    - name: ceph-csi-block
      persistentVolumeClaim:
        claimName: block-rbd-pvc
    - name: ceph-csi
      persistentVolumeClaim:
        claimName: filesystem-rbd-pvc
        # claimName: cephfs-pvc
EOF
}
#######################
download() {
    rbd=(
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/rbd/kubernetes/csidriver.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/rbd/kubernetes/csi-provisioner-rbac.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/rbd/kubernetes/csi-nodeplugin-rbac.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/rbd/kubernetes/csi-rbdplugin-provisioner.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/rbd/kubernetes/csi-rbdplugin.yaml
    )
    cephfs=(
        # # must check kubernetes & ceph version, Ceph CSI drivers must support!!
        # v3.8.0	Kubernetes	v1.24, v1.25, v1.26, v1.27
        # v3.7.2	Kubernetes	v1.22, v1.23, v1.24
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/cephfs/kubernetes/csidriver.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/cephfs/kubernetes/csi-cephfsplugin-provisioner.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/cephfs/kubernetes/csi-cephfsplugin.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/cephfs/kubernetes/csi-nodeplugin-rbac.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/cephfs/kubernetes/csi-provisioner-rbac.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/cephfs/kubernetes/csi-provisioner-psp.yaml
        https://raw.githubusercontent.com/ceph/ceph-csi/${CSI_VERSION}/deploy/cephfs/kubernetes/csi-nodeplugin-psp.yaml
    )
    log "CSI_VERSION=${CSI_VERSION}"
    for url in ${rbd[@]}; do
        fn="$(basename ${url})"
        log "download rbd ${url}"
        wget -q --no-check-certificate -O "rbd-${CSI_VERSION}-${fn}" "${url}" || true
    done
    for url in ${cephfs[@]}; do
        fn="$(basename ${url})"
        log "download cephfs ${url}"
        wget -q --no-check-certificate -O "cephfs-${CSI_VERSION}-${fn}" "${url}" || true
    done
    return 0
}
