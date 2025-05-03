<disk type='network' device='cdrom'>
  <driver name='qemu' type='raw'/>
    <source protocol="https" name="/{{ vm_uuid }}/cidata.iso">
      <host name="vmm.registry.local" port="443"/>
       <ssl verify="no"/>
    </source>
  <target dev='sd{{ vm_last_disk }}' bus='sata'/>
  <readonly/>
</disk>
