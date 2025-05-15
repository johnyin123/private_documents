{#RBD DISK#}
{%- macro getdev() %}{%- if disk_bus == 'ide' %}hd{{ vm_last_disk }}{%- elif disk_bus in ['sata', 'scsi'] %}sd{{ vm_last_disk }}{%- else %}vd{{ vm_last_disk }}{%- endif %}{%- endmacro %}
<disk type='network' device='disk'>
  <driver name='qemu' type='raw'/>
  <auth username='admin'><secret type='ceph' uuid='93916638-1ba4-448f-b789-8e7cf1313419'/></auth>
  <source protocol='rbd' name='ceph_libvirt_pool/{{ getdev() }}-{{ vm_uuid }}.raw'>
    <host name='172.16.16.20' port='6789'/>
    <host name='172.16.16.21' port='6789'/>
    <host name='172.16.16.22' port='6789'/>
    <host name='172.16.16.23' port='6789'/>
    <host name='172.16.16.24' port='6789'/>
  </source>
  <target dev='{{ getdev() }}' bus='{{ disk_bus | default("virtio") }}'/>
</disk>
