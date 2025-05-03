<disk type='file' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <target dev='sd{{ vm_last_disk }}' bus='sata'/>
  <readonly/>
</disk>
