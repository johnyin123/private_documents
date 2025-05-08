<disk type='network' device='cdrom'>
  <driver name='qemu' type='raw'/>
    <source protocol="https" name="/{{ vm_uuid }}/cidata.iso">
      <host name="{{ META_SRV }}" port="443"/>
       <ssl verify="no"/>
    </source>
  <target dev='sd{{ vm_last_disk }}' bus='sata'/>
  <readonly/>
</disk>
