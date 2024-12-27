cat <<'EOF'
FSID=$(ceph fsid)
ADMIN_KEY=$(ceph auth get-key client.${ADMIN_USER})
CEPHFS_NAME=$(ceph fs ls -f json | jq -r '.[0].name')

ceph config generate-minimal-conf > ceph.conf
ceph fs authorize <cephfs_name> client.<user> / rw > ceph.client.<user>.keyring
fsname=$(ceph fs volume ls | jq -r '.[0].name')
# ceph fs volume create ${fsname}
# ceph fs subvolumegroup create ${fsname} ${group}
# ceph fs subvolume create ${fsname} dirname ${group} --size=1073741824
# # /volumes/${group}/dirname/uuid....
# ceph fs subvolume ls ${fsname} ${group}
# ceph fs authorize ${fsname} client.${ceph_user} ${cephfs_path} rw
######## # # # euler cephfs BUG, ceph fs subvolume ls.... exception
## /volumes/${group}/dirname/uuid.....
# cephfs_path=$(ceph fs subvolume getpath ${fsname} testSubVolume ${group})

# # euler cephfs BUG
# ceph fs subvolume authorize <vol_name> <sub_name> <auth_id> [--group_name=<group_name>] [--access_level=<access_level>]
# ceph fs subvolume authorized_list <vol_name> <sub_name> 
ceph auth get-key client.${ceph_user}

# # create user for RBD
ceph auth get-or-create client.kubernetes \
    mon 'profile rbd' \
    osd 'profile rbd' \
    mgr 'allow rw'
# # create user for CephFS
ceph auth get-or-create client.kubernetes \
    mon 'allow r' \
    osd 'allow rw tag cephfs metadata=*' \
    mgr 'allow rw'
# # stage secret in storageclass, cephfs
ceph auth get-or-create client.kubernetes \
    mon 'allow r' \
    osd 'allow rw tag cephfs *=*' \
    mgr 'allow rw' \
    mds 'allow rw'

kubectl -n cephcsi exec -it csi-cephfsplugin-provisioner-xx -c csi-cephfsplugin -- /bin/bash
EOF

REGISTRY=registry.local
clusterid=fa0a4156-7196-416e-8ef2-b7c7328a4458
mons="172.16.16.2:6789,172.16.16.3:6789,172.16.16.4:6789,172.16.16.7:6789,172.16.16.8:6789"
NAMESPACE=cephcsi
CSI_VERSION=v3.7.2
TYPES=(rbd cephfs)
#######################
RBD_POOL=libvirt-pool
CEPHFS_NAME=tsdfs
ADMIN_USER=admin
ADMIN_KEY=AQAJ55xkhjuzGBAATpvjghofGpVMsSJ17icnJQ==

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
        "clusterID": "${clusterid}",
        "monitors": [ "$(echo "${mons}" | sed 's/,/","/g')" ],
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
  # Required for dynamically provisioned volumes
  userID: ${ADMIN_USER}
  userKey: ${ADMIN_KEY}
  $([ "${type}" == "cephfs" ] && { cat <<EO_ADMIN
  # Required for statically provisioned volumes
  adminID: ${ADMIN_USER}
  adminKey: ${ADMIN_KEY}
EO_ADMIN
})
  encryptionPassphrase: test_passphrase
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
  clusterID: ${clusterid}
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
