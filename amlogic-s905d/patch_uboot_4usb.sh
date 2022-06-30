#!/usr/bin/env bash

# patch u-boot.bin for USB usage!!!
org_tgts1="boot_targets=mmc0 mmc1 mmc2 usb0 pxe dhcp"
org_tgts2="boot_targets=romusb mmc0 mmc1 mmc2 usb0 pxe dhcp"

new_tgts1="boot_targets=usb0 mmc0 mmc1 mmc2 pxe dhcp"
new_tgts2="boot_targets=usb0 mmc0 mmc1 mmc2 pxe romusb dhcp"

xxd -p -c 2127800 u-boot.bin \
    | sed "s/$(echo -n ${org_tgts1} | xxd -p -c 500)/$(echo -n ${new_tgts1} | xxd -p -c 500)/g" \
    | sed "s/$(echo -n ${org_tgts2} | xxd -p -c 500)/$(echo -n ${new_tgts2} | xxd -p -c 500)/g" \
    | xxd -p -r > u-boot.usb.bin
strings u-boot.usb.bin | grep "boot_targets="

new_tgts1="boot_targets=mmc0 mmc1 mmc2 usb0 pxe dhcp"
new_tgts2="boot_targets=mmc0 mmc1 mmc2 usb0 pxe romusb dhcp"
xxd -p -c 2127800 u-boot.bin \
    | sed "s/$(echo -n ${org_tgts1} | xxd -p -c 500)/$(echo -n ${new_tgts1} | xxd -p -c 500)/g" \
    | sed "s/$(echo -n ${org_tgts2} | xxd -p -c 500)/$(echo -n ${new_tgts2} | xxd -p -c 500)/g" \
    | xxd -p -r > u-boot.mmc.bin
strings u-boot.mmc.bin | grep "boot_targets="

echo "patch pxe need u-boot.bin.new"
new_tgts1="boot_targets=pxe mmc0 mmc1 mmc2 usb0 dhcp"
new_tgts2="boot_targets=pxe mmc0 mmc1 mmc2 usb0 romusb dhcp"
xxd -p -c 2127800 u-boot.bin \
    | sed "s/$(echo -n ${org_tgts1} | xxd -p -c 500)/$(echo -n ${new_tgts1} | xxd -p -c 500)/g" \
    | sed "s/$(echo -n ${org_tgts2} | xxd -p -c 500)/$(echo -n ${new_tgts2} | xxd -p -c 500)/g" \
    | xxd -p -r > u-boot.pxe.bin
strings u-boot.pxe.bin | grep "boot_targets="

# ethaddr
