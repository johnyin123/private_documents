#!/usr/bin/env bash

pciid1="$(lspci -nn  | grep -oP 'VGA.*NVIDIA.*\[\K[\w:]+')"
pciid2="$(lspci -nn  | grep -oP 'Audio.*NVIDIA.*\[\K[\w:]+')"

echo "Setting modprobe to use VFIO for NVidia PCI ID's"
echo ""
cat << EOF > /etc/modprobe.d/vfio.conf
options vfio-pci ids=$pciid1,$pciid2
options vfio-pci disable_vga=1
EOF
cat /etc/modprobe.d/vfio.conf


echo "Blacklisting nouveau Drivers"
echo ""
cat << EOF > /etc/modprobe.d/blacklist.conf
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF
cat /etc/modprobe.d/blacklist.conf



if [ "$(cat /proc/cpuinfo  | grep intel)" ]; then
echo ""
echo "Intel CPU Found Setting intel_iommu=on"
echo "Configure Grub to Blacklist nouveau Drivers"
echo "Configure Grub to use vfio-pci Drivers"
sed -i 's,^\(GRUB_CMDLINE_LINUX[ ]*=\).*,\1"rhgb quiet intel_iommu=on iommu=pt rd.driver.pre=vfio-pci video=efifb:off rd.driver.blacklist=nouveau",g' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/^/#/g' /etc/default/grub
else
echo ""
echo "AMD CPU Found Setting amd_iommu=on"
echo "Configure Grub to Blacklist nouveau Drivers"
echo "Configure Grub to use vfio-pci Drivers"
sed -i 's,^\(GRUB_CMDLINE_LINUX[ ]*=\).*,\1"rhgb quiet amd_iommu=on iommu=pt rd.driver.pre=vfio-pci video=efifb:off rd.driver.blacklist=nouveau",g' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/^/#/g' /etc/default/grub
fi

cat /etc/default/grub | grep "GRUB_CMDLINE_LINUX"

if [ "$(grep -Ei 'debian|buntu|mint' /etc/*release)" ]; then
echo "Debian Based Release Found"
echo "Updating Grub2"
echo "options kvm ignore_msrs=1" > /etc/modprobe.d/kvm.conf
update-grub2
echo ""
else
echo "RHEL Based Release Found"
echo "Updating Grub via dracut"
grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r)-nouveau.img
dracut /boot/initramfs-$(uname -r).img $(uname -r)
sudo dracut -f --kver `uname -r`
echo ""
fi

ls /etc/modprobe.d/

while true; do
    read -p "Would You Like to Reboot Now? It is Required!" yn
    case $yn in
        [Yy]* ) reboot;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done


:<<"EOF"
<domain>
  <features>
    <kvm>
      <hidden state='on'/>
    </kvm>
  </features>
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='2' threads='1'/>
  </cpu>
  <devices>
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <driver name='vfio'/>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x1'/>
      </source>
      <alias name='hostdev0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </hostdev>
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <driver name='vfio'/>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
      </source>
      <alias name='hostdev1'/>
      <rom bar='on' file='/opt/palit1050ti.rom'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </hostdev>
    <hostdev mode='subsystem' type='usb' managed='yes'>
      <source>
        <vendor id='0x046d'/>
        <product id='0xc52b'/>
        <address bus='1' device='3'/>
      </source>
      <alias name='hostdev2'/>
      <address type='usb' bus='0' port='1'/>
    </hostdev>
    <hostdev mode='subsystem' type='usb' managed='yes'>
      <source>
        <vendor id='0x24ae'/>
        <product id='0x2000'/>
        <address bus='1' device='2'/>
      </source>
      <alias name='hostdev3'/>
      <address type='usb' bus='0' port='2'/>
    </hostdev>
  </devices>
</domain>
EOF
