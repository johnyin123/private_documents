<disk type='file' device='disk'>
   <driver name='qemu' type='raw' cache='none' io='native'/>
   <source file='/var/lib/libvirt/images/vd{{ vm_last_disk }}-{{ vm_uuid }}.raw'/>
   <backingstore/>
   <target dev='vd{{ vm_last_disk }}' bus='virtio'/>
</disk>
