#!/usr/bin/env bash
for ip in 16 17 18 19 20
do
    
    cat <<"EOF" | ssh -p60022 root@10.32.147.$ip
echo "nameserver 114.114.114.114" > /etc/resolv.conf
yum -y update && yum -y upgrade
yum -y install bridge-utils.x86_64
yum -y group install "Virtualization Host"

systemctl enable chronyd.service
systemctl start chronyd.service
timedatectl set-local-rtc 0

echo "enable libvirtd access over ssh"
sed -i "s/#unix_sock_group/unix_sock_group/g" /etc/libvirt/libvirtd.conf
sed -i "s/#unix_sock_rw_perms/unix_sock_rw_perms/g" /etc/libvirt/libvirtd.conf
systemctl restart libvirtd.service
systemctl enable libvirtd.service
usermod -G libvirt root

umount /home

mkdir -p /storage
sed  "/\/home/d" /etc/fstab > /tmp/fstab
grep "\/home" /etc/fstab | sed "s/defaults/rw,noexec,nodev,noatime,nodiratime,nobarrier/g" | sed "s_/home_/storage_g" >> /tmp/fstab
cat /tmp/fstab > /etc/fstab

mount -a
df -h

virsh pool-list
virsh pool-destroy default
virsh pool-delete default
virsh pool-undefine default

virsh pool-define-as default --type dir --target /storage
virsh pool-build default
virsh pool-start default
virsh pool-autostart default

virsh net-list --all
virsh net-undefine default
virsh net-destroy default

cat <<ENET | virsh net-define /dev/stdin
<network>
  <name>br-data.144</name>
  <forward mode='bridge'/>
  <bridge name='br-data.144'/>
</network>
ENET
cat <<ENET | virsh net-define /dev/stdin
<network>
  <name>br-data.145</name>
  <forward mode='bridge'/>
  <bridge name='br-data.145'/>
</network>
ENET
cat <<ENET | virsh net-define /dev/stdin
<network>
  <name>br-data.146</name>
  <forward mode='bridge'/>
  <bridge name='br-data.146'/>
</network>
ENET
cat <<ENET | virsh net-define /dev/stdin
<network>
  <name>br-data.149</name>
  <forward mode='bridge'/>
  <bridge name='br-data.149'/>
</network>
ENET

virsh net-autostart br-data.144
virsh net-autostart br-data.145
virsh net-autostart br-data.146
virsh net-autostart br-data.149
virsh net-start br-data.144
virsh net-start br-data.145
virsh net-start br-data.146
virsh net-start br-data.149
EOF
done


:<<"GPUEOF"

pciid1="$(lspci -nn  | grep -oP 'VGA.*NVIDIA.*\[\K[\w:]+')"
pciid2="$(lspci -nn  | grep -oP 'Audio.*NVIDIA.*\[\K[\w:]+')"

cat << EOF > /etc/modprobe.d/vfio.conf
options vfio-pci ids=$pciid1,$pciid2
# options vfio-pci disable_vga=1
EOF
cat << EOF > /etc/modprobe.d/blacklist.conf
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

cat <<EOF > /etc/modules-load.d/vfio-pci.conf
vfio-pci
EOF

eval $(grep -E "^GRUB_CMDLINE_LINUX=.*" /etc/default/grub)
GRUB_CMDLINE_LINUX+=" intel_iommu=on iommu=pt rd.driver.pre=vfio-pci video=efifb:off rd.driver.blacklist=nouveau"
sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE_LINUX\"/g" /etc/default/grub

cat /etc/default/grub

grub2-mkconfig -o /boot/grub2/grub.cfg
dracut -f --kver `uname -r`



# $lspci | grep VGP
# 3b:00.0 VGA compatible controller: NVIDIA Corporation GP104GL [Quadro P5000] (rev a1)

virt-install ....... \
--host-device 3b:00.0 \
--machine q35

libvirtd:
     <hostdev mode='subsystem' type='pci' managed='yes'>
      <driver name='vfio'/>
      <source>
        <address domain='0x0000' bus='0x3b' slot='0x00' function='0x0'/>
      </source>
      <alias name='hostdev0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
     </hostdev>
GPUEOF
