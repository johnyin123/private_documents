export VIP=192.168.0.100
export INTERFACE=eth0
ctr image pull docker.io/plndr/kube-vip:0.3.1
ctr run --rm --net-host docker.io/plndr/kube-vip:0.3.1 vip \
/kube-vip manifest pod \
--interface $INTERFACE \
--vip $VIP \
--controlplane \
--services \
--arp \
--leaderElection | tee  /etc/kubernetes/manifests/kube-vip.yaml

