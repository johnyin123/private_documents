{%- macro getdev() %}{%- if disk_bus == 'ide' %}hd{{ vm_last_disk }}{%- elif disk_bus in ['sata', 'scsi'] %}sd{{ vm_last_disk }}{%- else %}vd{{ vm_last_disk }}{%- endif %}{%- endmacro %}
<disk type='file' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <target dev='{{ getdev() }}' bus='{{ disk_bus | default("virtio") }}'/>
  <readonly/>
</disk>
