DISK=$(virsh dumpxml domname | xmllint --xpath 'string(/domain/devices/disk/alias/@name)' -)
#--<alias name="virtio-disk0"/>
virsh qemu-monitor-command domname block_resize drive-${DISK} 30G --hmp

test on rbd storage for kvm
