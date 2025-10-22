{#-本地文件DISK-#}
{%- macro getdev() %}{%- if vm_disk_bus == 'ide' %}hd{{ vm_last_disk }}{%- elif vm_disk_bus in ['sata', 'scsi'] %}sd{{ vm_last_disk }}{%- else %}vd{{ vm_last_disk }}{%- endif %}{%- endmacro %}
<disk type='file' device='disk'>
   <driver name='qemu' type='{{vm_disk_type | default("raw", true)}}' cache='none' io='native'/>
   <source file='/storage/{{ getdev() }}-{{ vm_uuid }}.{{vm_disk_type | default("raw", true)}}'/>
   <backingstore/>
   <target dev='{{ getdev() }}' bus='{{ vm_disk_bus | default("virtio", true) }}'/>
</disk>
