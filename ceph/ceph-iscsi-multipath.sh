#!/usr/bin/env bash
# # check on debian(target), openeuler(iscsi-initiator)
iscsi server: apt -y install tgt tgt-rbd ceph-common
# 部署多个iscsi节点,可以识别同一个wwid,组成多路径
# /etc/ceph/ceph.client.admin.keyring
cat <<EOF >/etc/ceph/ceph.conf
[global]
fsid = xxxxxx
mon_host = ip1,ip2
EOF
cat <<EOF > /etc/tgt/conf.d/rbd.conf
<target iqn.2024-11.rbd.local:iscsi-01>
driver iscsi
bs-type rbd
conf=/etc/ceph/ceph.conf
id=client.admin
# cluster=<cluster name>
backing-store libvirt-pool/rbd.img
</target>
EOF
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
iscsi client: apt -y install multipath-tools open-iscsi
              yum -y install multipath-tools open-iscsi

systemctl enable iscsid.service  --now
systemctl enable multipathd.service --now
cat <<EOF
iscsiadm -m session -o show
iscsiadm --mode discoverydb --type sendtargets --portal <ip> --discover
# # automatic startup & login
# target name: iqn.2024-11.rbd.local:iscsi-01
iscsiadm --mode node -T <target name> -p <ip> --op update -n node.startup -v automatic
# # re-login manually
iscsiadm --mode node --portal <ip> --login
#  iscsiadm --mode node --op delete

# # force remove device
# echo 1 > /sys/block/<name>/device/delete
# When the last block device for the volume is deleted, multipath will remove the virtual block device.
EOF
multipath -ll
ls -l /dev/mapper/
