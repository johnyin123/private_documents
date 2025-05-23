{#无盘CDROM#}
{%- macro getdev() %}{%- if disk_bus == 'ide' %}hd{{ vm_last_disk }}{%- else %}sd{{ vm_last_disk }}{%- endif %}{%- endmacro %}
<disk type='file' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <target dev='{{ getdev() }}' bus='{{ disk_bus | default("sata") }}'/>
  <readonly/>
</disk>
