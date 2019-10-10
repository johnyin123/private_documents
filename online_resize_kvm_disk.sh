# xmllint --xpath '//element/@attribute' file.xml
# xmlstarlet sel -t -v "//element/@attribute" file.xml
# xpath -q -e '//element/@attribute' file.xml
# xidel -se '//element/@attribute' file.xml
# saxon-lint --xpath '//element/@attribute' file.xml

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
<volume type='network'>
  <name>data-8059d256-b575-414f-bedf-ea91914e4bb7.raw</name>
  <key>cephpool/data-8059d256-b575-414f-bedf-ea91914e4bb7.raw</key>
  <source>
  </source>
  <capacity unit='GiB'>500</capacity>
  <allocation unit='GiB'>500</allocation>
  <target>
    <path>cephpool/data-8059d256-b575-414f-bedf-ea91914e4bb7.raw</path>
    <format type='raw'/>
  </target>
</volume>
" > disk.xml
virsh vol-create cephpool disk.xml
virsh vol-create-as cephpool test.raw 5G
# virsh vol-delete test.raw --pool cephpool

echo "
    <disk type='network' device='disk'>
      <driver name='qemu' type='raw'/>
      <auth username='libvirt'>
        <secret type='ceph' uuid='2dfb5a49-a4e9-493a-a56f-4bd1bf26a149'/>
      </auth>
      <source protocol='rbd' name='cephpool/data-8059d256-b575-414f-bedf-ea91914e4bb7.raw'>
        <host name='node01' port='6789'/>
        <host name='node02' port='6789'/>
        <host name='node03' port='6789'/>
        <host name='node04' port='6789'/>
        <host name='node05' port='6789'/>
        <host name='node06' port='6789'/>
        <host name='node07' port='6789'/>
      </source>
      <target dev='vdb' bus='virtio'/>
    </disk>
" > device.xml

virsh attach-device dom_name device.xml --persistent 



# mkdir /root/.ssh
virsh qemu-agent-command ${DOMAIN} '{"execute":"guest-exec","arguments":{"path":"mkdir","arg":["-p","/root/.ssh"],"capture-output":true}}'

# 假设上一步返回{"return":{"pid":911}}，接下来查看结果（通常可忽略）
virsh qemu-agent-command ${DOMAIN} '{"execute":"guest-exec-status","arguments":{"pid":911}}'

# chmod 700 /root/.ssh，此行其实可不执行，因为上面创建目录后就是700，但为了防止权限不正确导致无法使用，这里还是再刷一次700比较稳妥
virsh qemu-agent-command ${DOMAIN} '{"execute":"guest-exec","arguments":{"path":"chmod","arg":["700","/root/.ssh"],"capture-output":true}}'

# 假设上一步返回{"return":{"pid":912}}，接下来查看结果（通常可忽略）
virsh qemu-agent-command ${DOMAIN} '{"execute":"guest-exec-status","arguments":{"pid":912}}'



#snapshot
qemu-img snapshot -c sp0 rbd:rbd/fedora -f raw
#rollback
qemu-img snapshot -a sp0 rbd:rbd/fedora
#del snapshot
qemu-img snapshot -d sp0 rbd:rbd/fedora
#list snapshot
rbd snap ls rbd/fedora
qemu-img snapshot -l rbd:rbd/fedora
