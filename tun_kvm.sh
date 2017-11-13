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
