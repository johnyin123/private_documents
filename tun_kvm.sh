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
