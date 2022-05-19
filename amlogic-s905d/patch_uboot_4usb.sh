#!/usr/bin/env bash

# patch u-boot.bin for USB usage!!!
boot_targets="mmc0 mmc1 mmc2 usb0"
new_tgts="usb0 usb1 mmc0 mmc1"
bootcmd_mmc2="bootcmd_mmc2=devnum=2; run mmc_boot"
bootcmd_usb1="bootcmd_usb1=devnum=1; run usb_boot"
xxd -p -c 2127800 u-boot.bin \
    | sed "s/$(echo -n ${boot_targets} | xxd -p -c 500)/$(echo -n ${new_tgts} | xxd -p -c 500)/g" \
    | sed "s/$(echo -n ${bootcmd_mmc2} | xxd -p -c 500)/$(echo -n ${bootcmd_usb1} | xxd -p -c 500)/g" \
    | xxd -p -r > u-boot.usb.bin

# ethaddr
