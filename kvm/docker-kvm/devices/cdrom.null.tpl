{#-无盘CDROM-#}
{%- macro getdev() %}{%- if vm_disk_bus == 'ide' %}hd{{ vm_last_disk }}{%- else %}sd{{ vm_last_disk }}{%- endif %}{%- endmacro %}
<disk type='file' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <target dev='{{ getdev() }}' bus='{{ vm_disk_bus | default("sata", true) }}'/>
  <readonly/>
</disk>
