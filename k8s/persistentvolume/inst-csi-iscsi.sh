# # https://github.com/kubernetes-csi/csi-driver-iscsi
# arm64 image ERROR wrong arch
kubectl -n kube-system get pod -o wide -l app=csi-iscsi-node
kubectl logs -f csi-iscsi-node-c94g2 -c iscsi -n kube-system
