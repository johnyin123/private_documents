<disk type='file' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <target dev='hd{{ vm_last_disk }}' bus='ide'/>
  <readonly/>
</disk>
