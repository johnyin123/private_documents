#Live migrate a libvirt/kvm virtual machine with both local and shared storage
virsh migrate ${VM} qemu+ssh://user@server:port/system --copy-storage-all --persistent --undefinesource 


DISK=$(virsh dumpxml domname | xmllint --xpath 'string(/domain/devices/disk/alias/@name)' -)
#--<alias name="virtio-disk0"/>
virsh qemu-monitor-command domname block_resize drive-${DISK} 30G --hmp

#test on rbd storage for kvm

virsh attach-disk ${vmname} --source /storage/${image} --target vdb --cache none --io native --persistent --live
#test on file store for kvm

virsh qemu-monitor-command domname balloon 1024 --hmp
virsh qemu-monitor-command domname info balloon --hmp

#XFS
# simple flat partition just fdisk del partition,and create OK
#xfs_growfs /share

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

echo "
    <disk type='network' device='disk'>
      <driver name='qemu' type='raw'/>
      <auth username='vmimages'>
        <secret type='ceph' uuid='xxx'/>
      </auth>
      <source protocol='rbd' name='vmimages/ubuntu-newdrive'>
        <host name='192.168.0.102' port='6789'/>
      </source>
      <target dev='vdz' bus='virtio'/>
    </disk>
" > device.xml

virsh attach-device ubuntu device.xml --persistent 



# mkdir /root/.ssh
virsh qemu-agent-command ${DOMAIN} '{"execute":"guest-exec","arguments":{"path":"mkdir","arg":["-p","/root/.ssh"],"capture-output":true}}'

# 假设上一步返回{"return":{"pid":911}}，接下来查看结果（通常可忽略）
virsh qemu-agent-command ${DOMAIN} '{"execute":"guest-exec-status","arguments":{"pid":911}}'

# chmod 700 /root/.ssh，此行其实可不执行，因为上面创建目录后就是700，但为了防止权限不正确导致无法使用，这里还是再刷一次700比较稳妥
virsh qemu-agent-command ${DOMAIN} '{"execute":"guest-exec","arguments":{"path":"chmod","arg":["700","/root/.ssh"],"capture-output":true}}'

# 假设上一步返回{"return":{"pid":912}}，接下来查看结果（通常可忽略）
virsh qemu-agent-command ${DOMAIN} '{"execute":"guest-exec-status","arguments":{"pid":912}}'
