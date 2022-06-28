#!/usr/bin/env bash

# patch u-boot.bin for USB usage!!!
org_tgts1="boot_targets=mmc0 mmc1 mmc2 usb0 pxe dhcp"
new_tgts1="boot_targets=pxe usb0 usb1 mmc0 mmc1 dhcp"

org_tgts2="boot_targets=romusb mmc0 mmc1 mmc2 usb0 pxe dhcp"
new_tgts2="boot_targets=pxe usb0 usb1 mmc0 mmc1 romusb dhcp"

bootcmd_mmc2="bootcmd_mmc2=devnum=2; run mmc_boot"
bootcmd_usb1="bootcmd_usb1=devnum=1; run usb_boot"

xxd -p -c 2127800 u-boot.bin \
    | sed "s/$(echo -n ${org_tgts1} | xxd -p -c 500)/$(echo -n ${new_tgts1} | xxd -p -c 500)/g" \
    | sed "s/$(echo -n ${org_tgts2} | xxd -p -c 500)/$(echo -n ${new_tgts2} | xxd -p -c 500)/g" \
    | sed "s/$(echo -n ${bootcmd_mmc2} | xxd -p -c 500)/$(echo -n ${bootcmd_usb1} | xxd -p -c 500)/g" \
    | xxd -p -r > u-boot.usb.bin

new_tgts1="boot_targets=pxe mmc0 mmc1 usb0 usb1 dhcp"
new_tgts2="boot_targets=pxe mmc0 mmc1 usb0 usb1 romusb dhcp"
xxd -p -c 2127800 u-boot.bin \
    | sed "s/$(echo -n ${org_tgts1} | xxd -p -c 500)/$(echo -n ${new_tgts1} | xxd -p -c 500)/g" \
    | sed "s/$(echo -n ${org_tgts2} | xxd -p -c 500)/$(echo -n ${new_tgts2} | xxd -p -c 500)/g" \
    | sed "s/$(echo -n ${bootcmd_mmc2} | xxd -p -c 500)/$(echo -n ${bootcmd_usb1} | xxd -p -c 500)/g" \
    | xxd -p -r > u-boot.mmc.bin

# ethaddr
