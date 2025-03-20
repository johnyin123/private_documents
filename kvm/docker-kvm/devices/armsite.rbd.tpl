<disk type='network' device='disk'>
  <driver name='qemu' type='raw'/>
  <auth username='admin'><secret type='ceph' uuid='f36b7dbf-cc30-4255-92de-8adb86cdb346'/></auth>
  <source protocol='rbd' name='ceph_libvirt_pool/vd{{ vm_last_disk }}-{{ vm_uuid }}.raw'>
    <host name='172.16.16.2' port='6789'/>
    <host name='172.16.16.3' port='6789'/>
    <host name='172.16.16.4' port='6789'/>
    <host name='172.16.16.7' port='6789'/>
    <host name='172.16.16.8' port='6789'/>
  </source>
  <target dev='vd{{ vm_last_disk }}' bus='virtio'/>
</disk>
