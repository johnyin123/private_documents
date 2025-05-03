<disk type='network' device='disk'>
  <driver name='qemu' type='raw'/>
  <auth username='admin'><secret type='ceph' uuid='93916638-1ba4-448f-b789-8e7cf1313419'/></auth>
  <source protocol='rbd' name='ceph_libvirt_pool/vd{{ vm_last_disk }}-{{ vm_uuid }}.raw'>
    <host name='172.16.16.20' port='6789'/>
    <host name='172.16.16.21' port='6789'/>
    <host name='172.16.16.22' port='6789'/>
    <host name='172.16.16.23' port='6789'/>
    <host name='172.16.16.24' port='6789'/>
  </source>
  <target dev='vd{{ vm_last_disk }}' bus='virtio'/>
</disk>
