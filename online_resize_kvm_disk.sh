DISK=$(virsh dumpxml domname | xmllint --xpath 'string(/domain/devices/disk/alias/@name)' -)
#--<alias name="virtio-disk0"/>
virsh qemu-monitor-command domname block_resize drive-${DISK} 30G --hmp

test on rbd storage for kvm


virsh qemu-monitor-command domname balloon 1024 --hmp
virsh qemu-monitor-command domname info balloon --hmp



#    qemu-img resize -f rbd rbd:sata/disk3 40G
#    virsh domblklist rbd-test
#    > Target     Source
#    > ------------------------------------------------
#    > vdb        sata/disk2-qemu-5g:rbd_cache=1
#    > vdc        sata/disk3:rbd_cache=1
#    > hdc        -
#    Then use virsh to tell the guest that the disk has a new size:
#    virsh blockresize --domain rbd-test --path "vdc" --size 40G
#    > Block device 'vdc' is resized
#    Check raw rbd info
#    rbd --pool sata info disk3
#    > rbd image 'disk3':
#    >        size 40960 MB in 10240 objects
#    >        order 22 (4096 KB objects)
#    >        block_name_prefix: rb.0.13fb.23353e97
#    >        parent:  (pool -1)
#    Make sure you can see the change from dmesg (Guest should see the new size change).


