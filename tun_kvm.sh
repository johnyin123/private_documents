echo "2048">/proc/sys/vm/nr_hugepages
mkdir -p /hugetlbfs
mount -t hugetlbfs hugetlbfs /hugetlbfs
mkdir -p /hugetlbfs/libvirt/bin
systemctl restart libvirtd

cat /proc/meminfo | grep HugePages_

Add below codes after the line "<currentMemory ..."
<memoryBacking>
  <hugepages/>
</memoryBacking>

# lvcreate -L25G -s -n snap-webserver /dev/storage/webserver
#import LVM image via ssh to remote host
# Using format 2 rbd images 
# dd if=/dev/e0.0/snap-webhotel | pv | ssh root@remote-server 'rbd --image-format 2 import - sata/webserver'

## Optional; create a snapshot first
# rbd snap create sata/webserver@snap1
## Transfer image
# rbd export sata/webserver@snap1 - | pv | ssh root@remote-server 'dd of=/dev/lvm-storage/webserver'

# rbd map libvirt-pool/template.raw
# rbd resize libvirt-pool/template.raw --size 8G
# growpart /dev/rbd0 1
# mount /dev/rbd0p1 /mnt
# xfs_growfs -d  -l  /mnt
# umount /mnt
# xfs_repair /dev/rbd0p1
# rbd unmap /dev/rbd0

# qemu-img convert -f qcow2 -O raw debian_squeeze.qcow2 rbd:data/squeeze
# virsh start $VMNAME
# ping -c1 -W2 ${ip} >/dev/null 2>&1 && echo OK || echo ERR

# mount -o loop,offset=32256,uid=1000,gid=1000  fat32.dsk  ${mnt_point}
# modprobe nbd max_part=63
# qemu-nbd -c /dev/nbd0 fat32.dsk
# mount /dev/nbd0p1 -o uid=1000,gid=1000 ${mnt_point}
# qemu-nbd -d /dev/nbd0


# qemu-img resize -f raw demo.disk +1G
# fdisk demo.disk #add new partitions
# fdisk -l demo.disk
# kpartx -av demo.disk 
# ll /dev/mapper/loop0p1 
# mkfs.xfs /dev/mapper/loop0p2 
# kpartx -d demo.disk 


