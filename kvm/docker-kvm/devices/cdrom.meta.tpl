{%- macro getdev() %}{%- if disk_bus == 'ide' %}hd{{ vm_last_disk }}{%- else %}sd{{ vm_last_disk }}{%- endif %}
{%- endmacro %}
<disk type='network' device='cdrom'>
  <driver name='qemu' type='raw'/>
    <source protocol="https" name="/{{ vm_uuid }}/cidata.iso">
      <host name="{{ META_SRV }}" port="443"/>
       <ssl verify="no"/>
    </source>
  <target dev='{{ getdev() }}' bus='{{ disk_bus | default("scsi") }}'/>
  <readonly/>
</disk>
