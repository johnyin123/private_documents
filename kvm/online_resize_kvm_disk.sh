### add below to rc.local, chmod 755 /etc/rc.local for auto increase rootfs
disk=/dev/vda
part_no=2 #uefi
[ -d "/sys/firmware/efi" ] && part_no=2 || part_no=1
echo ,+ | sfdisk --force -u S -N ${part_no} ${disk} || true
partx -u ${disk} || true
case "$(lsblk -no FSTYPE ${disk}${part_no})" in
    xfs)   xfs_growfs $(lsblk -no MOUNTPOINT ${disk}${part_no}) || true ;;
    ext4)  resize2fs ${disk}${part_no} || true ;;
esac
cat <<EOF > /etc/rc.local
#!/bin/sh -e
exit 0
EOF
### END ###

# # extend  vda1
# extend all
echo ,+ | sfdisk --force -u S -N 1 /dev/vda || true
# extend to 4G
echo ,4G | sfdisk --force --unit S --partno 1 /dev/vda || true
# grow 2G
echo ,+2G | sfdisk --force --unit S --partno 1 /dev/vda || true
partx -u /dev/vda
xfs_growfs /dev/vda1

virsh attach-interface --domain pxe --type bridge --source br1 --model virtio --config --live

nmcli con add type bridge con-name br0 ifname br0 autoconnect yes
nmcli connection modify br0 ipv4.addresses 192.168.10.5/24 ipv4.method manual ipv4.gateway 192.168.10.1  ipv4.dns  8.8.8.8
nmcli con up br0

#BONDING_OPTS="mode=4 miimon=100 xmit_hash_policy=layer3+4" mode=802.3ad
#BONDING_OPTS="mode=802.3ad miimon=100 lacp_rate=fast xmit_hash_policy=layer2+3"
#BONDING_OPTS='mode=6 miimon=100

# change partition
#   sfdisk --unit=S --dump disk.raw > dump.out
#   truncate
#   sfdisk --no-reread disk.raw --backup-file my.save < dump.out
#   mount && xfs_growfs


# xmllint --xpath '//element/@attribute' file.xml
# xmlstarlet sel -t -v "//element/@attribute" file.xml
# xpath -q -e '//element/@attribute' file.xml
# xidel -se '//element/@attribute' file.xml
# saxon-lint --xpath '//element/@attribute' file.xml

#Live migrate a libvirt/kvm virtual machine with both local and shared storage
virsh migrate ${VM} qemu+ssh://user@server:port/system --copy-storage-all --persistent --undefinesource 


virsh qemu-monitor-command ${VM} --pretty '{ "execute": "query-commands"}'

#DISK=$(virsh dumpxml domname | xmllint --xpath 'string(/domain/devices/disk[1]/alias/@name)' -)

DOMNAME=
virsh domblklist ${DOMNAME}
TARGET=vda
DISK=$(virsh dumpxml ${DOMNAME} | xmllint --xpath "string(/domain/devices/disk/target[@dev=\"${TARGET}\"]/following-sibling::alias/@name)" -)
#--<alias name="virtio-disk0"/>
virsh qemu-monitor-command ${DOMNAME} block_resize drive-${DISK} 30G --hmp
#pvscan; pvresize /dev/vdb ; lvextend -l +100%FREE /dev/mapper/vg_data-lv_data
#        echo "[] linux-rootfs-resize ..."
#        lvm vgchange -an
#        lvm_pv_path=$(lvm pvs --noheadings |awk '{print $1}')
#        lvm_pv_temp=$(echo ${lvm_pv_path}|sed "s/dev//g")
#        lvm_pv_dev=$(echo ${lvm_pv_temp}| sed "s/[^a-z]//g")
#        lvm_pv_part=$(echo ${lvm_pv_temp}| sed "s/[^0-9]//g")
#        echo "${lvm_pv_dev} ${lvm_pv_part}"
#        growpart -v /dev/${lvm_pv_dev} ${lvm_pv_part}
#        lvm pvresize -v ${lvm_pv_path}
#        lvm vgchange --sysinit -ay
#        lvm lvresize -v -l +100%FREE ${ROOT}
# resize2fs/xfs_growfs/
#test on rbd storage for kvm

virsh attach-disk ${vmname} --source /storage/${image} --target vdb --cache none --io native --persistent --live
# Detach the disk
virsh detach-disk ${vmname} $disk --persistent --live
#test on file store for kvm

virsh qemu-monitor-command domname balloon 1024 --hmp
virsh qemu-monitor-command domname info balloon --hmp
virsh setvcpu ...

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


echo "New add_vm.sh"
cat <<EOFF
vmname=xxx
uuid=$(cat /proc/sys/kernel/random/uuid)
title=title
desc="desc desc"
memsize=$((2*1024*1024))
vcpus=4

cat <<EOVM | virsh define --file /dev/stdin
<domain type='kvm'>
  <name>${vmname}</name>
  <uuid>${uuid}</uuid>
  <title>${title}</title>
  <description>${desc}</description>
  <memory unit='KiB'>$((${memsize}*2))</memory>
  <currentMemory unit='KiB'>${memsize}</currentMemory>
  <vcpu placement='static' current='2'>${vcpus}</vcpu>
  <cpu match='exact'><model fallback='allow'>Westmere</model></cpu>
  <os>
    <type arch='x86_64'>hvm</type>
  </os>
  <features>
    <acpi/><apic/><pae/>
  </features>
  <on_poweroff>preserve</on_poweroff>
  <devices>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>
    <controller type='usb' index='0' model='ich9-ehci1'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x7'/>
    </controller>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='3'/>
    </redirdev>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </memballoon>
  </devices>
</domain>
EOVM

#qemu-img convert -f raw -O raw tpl.raw rbd:data/squeeze
pool=default
virsh -q vol-create-as --pool ${pool} --name sys_${uuid}.raw --capacity 1M  --format raw
virsh -q vol-resize  --pool ${pool} --vol sys_${uuid}.raw --capacity 5G
virsh -q vol-upload --pool ${pool} --vol sys_${uuid}.raw --file tpl.raw

cat <<EODISK | virsh attach-device ${uuid} --file /dev/stdin --persistent
<disk type='file' device='disk'>
   <driver name='qemu' type='raw' cache='none' io='native'/>
   <source file='/home/johnyin/disk/myvm/sys_${uuid}.raw'/>
   <backingStore/>
   <target dev='vda' bus='virtio'/>
</disk>
EODISK

cat <<EONET | virsh attach-device ${uuid} --file /dev/stdin --persistent
<interface type='network'>
  <source network='br-ext'/>
  <model type='virtio'/>
  <driver name="vhost"/>
</interface>
EONET
EOFF

echo "mount -t virtiofs mount_tag /mnt/mount/path"
echo "virtiofs requires shared memory, add sharemem before devices"
cat <<EOF
<memoryBacking>
  <source type='memfd'/>
  <access mode='shared'/>
</memoryBacking>
EOF
cat <<EOF
<filesystem type='mount' accessmode='passthrough'>
  <driver type='virtiofs'/>
  <source dir='path to source folder on host'/>
  <target dir='mount_tag'/>
</filesystem>
EOF
echo "9p: mount -t 9p diskshare /mnt"
cat <<EOF
    <filesystem type='mount' accessmode='mapped'>
      <source dir='/home/johnyin'/>
      <target dir='diskshare'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x0'/>
    </filesystem>
EOF


echo"Calculating CPU usage of guestos(kvm) use cgroup"
cat <<'EOF'
KVM_PID=47238
cgroup=$(grep cpuacct /proc/${KVM_PID}/cgroup | awk -F: '{ print $3 }')
tstart=$(date +%s%N)
cstart=$(cat /sys/fs/cgroup/cpu/$cgroup/cpuacct.usage)

sleep 5

tstop=$(date +%s%N)
cstop=$(cat /sys/fs/cgroup/cpu/$cgroup/cpuacct.usage)

bc -l <<BCEOF
($cstop - $cstart) / ($tstop - $tstart) * 100
BCEOF
EOF
