{#本地文件DISK#}
{%- macro getdev() %}{%- if disk_bus == 'ide' %}hd{{ vm_last_disk }}{%- elif disk_bus in ['sata', 'scsi'] %}sd{{ vm_last_disk }}{%- else %}vd{{ vm_last_disk }}{%- endif %}{%- endmacro %}
<disk type='file' device='disk'>
   <driver name='qemu' type='raw' cache='none' io='native'/>
   <source file='/storage/{{ getdev() }}-{{ vm_uuid }}.raw'/>
   <backingstore/>
   <target dev='{{ getdev() }}' bus='{{ disk_bus | default("virtio") }}'/>
</disk>
