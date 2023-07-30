insec_registry=192.168.168.250
provisioner_name=k8s-sigs.io/nfs-subdir-external-provisioner # 和StorageClass中provisioner保持一致便可
nfs_server=192.168.168.250
nfs_path=/nfsroot
name_space=default
kubectl create namespace ${name_space} || true
cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: nfs-provisioner
EOF
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
  namespace: ${name_space}
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["create", "delete", "get", "list", "watch", "patch", "update"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: ${name_space}
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: ${name_space}
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: ${name_space}
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: ${name_space}
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl get sa

cat << EOF | kubectl apply -f -
kind: Deployment
apiVersion: apps/v1
metadata:
  name: nfs-client-provisioner
  labels:
    app: nfs-client-provisioner
  namespace: ${name_space}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-client-provisioner
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          # quay.io/external_storage/nfs-client-provisioner:latest
          # registry.k8s.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
          image: ${insec_registry}/external_storage/nfs-client-provisioner:latest
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: ${provisioner_name}
            - name: NFS_SERVER
              value: ${nfs_server}
            - name: NFS_PATH
              value: ${nfs_path}
      volumes:
        - name: nfs-client-root
          nfs:
            server: ${nfs_server}
            path: ${nfs_path}
EOF

sc_name=nfs-sc
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${sc_name}
  namespace: ${name_space}
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ${provisioner_name}
EOF
kubectl get sc

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-${sc_name}
  namespace: ${name_space}
spec:
  storageClassName: ${sc_name}
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
EOF
kubectl get pvc
# #  unexpected error getting claim reference: selfLink was empty, can't make reference
# # /etc/kubernetes/manifests/kube-apiserver.yaml 添加参数
# # 增加 - --feature-gates=RemoveSelfLink=false
# # kubectl apply -f /etc/kubernetes/manifests/kube-apiserver.yaml
# OR
# # kubectl delete pod kube-apiserver-master01 -n kube-system
# # kubectl delete pod kube-apiserver-master02 -n kube-system
# # kubectl delete pod kube-apiserver-master03 -n kube-system
cat <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-pod
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mytest
  template:
    metadata:
      labels:
        app: mytest
    spec:
      volumes:
      - name: my-pvc-nfs
        persistentVolumeClaim:
          claimName: pvc-nfs-sc
      containers:
      - name: example-storage
        image: 192.168.168.250/library/busybox:latest
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c']
        args: ['echo "The host is $(hostname)" >> /dir/data; sleep 3600']
        volumeMounts:
        - name: my-pvc-nfs # template.spec.volumes[].name
          mountPath: /dir # mount inside of container
          readOnly: false
EOF
# @@ -204,12 +204,15 @@ init_calico_cni() {
# +    local insec_registry=192.168.168.250
# +    sed -i "s|spec\s*:\s*$|spec:\n  registry: ${insec_registry}|g" "${calico_cust_yml}"
# +    sed -i "s|image\s*:.*operator|image: ${insec_registry=}/tigera/operator|g" "${calico_yml}"
# @@ -336,7 +338,7 @@ EOF
# -        local pausekey=$(kubeadm config images list --kubernetes-version=${k8s_version} 2>/dev/null | grep pause)
# +        local pausekey=$(kubeadm config images list --image-repository ${insec_registry}/google_containers --kubernetes-version=${k8s_version} 2>/dev/null | grep pause)
#          echo "PAUSE:  ************** ${pausekey}"
# @@ -461,7 +463,7 @@ init_first_k8s_master() {
# -    local opts="--control-plane-endpoint ${api_srv} --upload-certs ${pod_cidr:+--pod-network-cidr=${pod_cidr}} ${svc_cidr:+--service-cidr ${svc_cidr}} --apiserver-advertise-address=0.0.0.0"
# +    local opts="--control-plane-endpoint ${api_srv} --upload-certs ${pod_cidr:+--pod-network-cidr=${pod_cidr}} ${svc_cidr:+--service-cidr ${svc_cidr}} --apiserver-advertise-address=0.0.0.0 --image-repository=192.168.168.250/google_containers"
# -    for ipaddr in $(array_print master) $(array_print worker); do
# -        prepare_k8s_images "${ipaddr}" CALICO_MAP "docker.io/calico"
# -        prepare_k8s_images "${ipaddr}" CALICO_OPER_MAP "quay.io/tigera"
# -    done
