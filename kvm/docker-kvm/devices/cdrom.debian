<disk type='network' device='cdrom'>
  <driver name='qemu' type='raw'/>
    <source protocol="http" name="/iso/debian.trixie.iso">
      <host name="kvm.registry.local" port="80"/>
    </source>
  <target dev='sd{{ vm_last_disk }}' bus='sata'/>
  <readonly/>
</disk>
