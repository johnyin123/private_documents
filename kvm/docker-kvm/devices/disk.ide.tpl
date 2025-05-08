<disk type='file' device='disk'>
   <driver name='qemu' type='raw' cache='none' io='native'/>
   <source file='/storage/hd{{ vm_last_disk }}-{{ vm_uuid }}.raw'/>
   <backingstore/>
   <target dev='hd{{ vm_last_disk }}' bus='ide'/>
</disk>
