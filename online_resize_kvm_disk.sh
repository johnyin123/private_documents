virsh dumpxml domname | xmllint --xpath '/domain/devices/disk/alias' -
#--<alias name="virtio-disk0"/>
virsh qemu-monitor-command domname block_resize drive-virtio-disk0 30G --hmp

test on rbd storage for kvm
