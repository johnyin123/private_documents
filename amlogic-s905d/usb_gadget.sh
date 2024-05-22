#!/bin/bash

set -euf -o pipefail

readonly GADGET_BASE_DIR="/sys/kernel/config/usb_gadget/g1"
readonly DEV_ETH_ADDR="aa:bb:cc:dd:ee:f1"
readonly HOST_ETH_ADDR="aa:bb:cc:dd:ee:f2"
readonly USBDISK="/usbdisk.img"

modprobe -r g_ether usb_f_ecm u_ether
modprobe libcomposite

# Create directory structure
mkdir "${GADGET_BASE_DIR}"
cd "${GADGET_BASE_DIR}"
mkdir -p configs/c.1/strings/0x409
mkdir -p strings/0x409

# Serial device
###
mkdir functions/acm.usb0
ln -s functions/acm.usb0 configs/c.1/
###

# Ethernet device
###
mkdir functions/ecm.usb0
echo "${DEV_ETH_ADDR}" > functions/ecm.usb0/dev_addr
echo "${HOST_ETH_ADDR}" > functions/ecm.usb0/host_addr
ln -s functions/ecm.usb0 configs/c.1/
###

# Mass Storage device
###
mkdir functions/mass_storage.usb0
echo 1 > functions/mass_storage.usb0/stall
echo 0 > functions/mass_storage.usb0/lun.0/cdrom
echo 0 > functions/mass_storage.usb0/lun.0/ro
echo 0 > functions/mass_storage.usb0/lun.0/nofua
echo "${USBDISK}" > functions/mass_storage.usb0/lun.0/file
ln -s functions/mass_storage.usb0 configs/c.1/
###

# Composite Gadget Setup
echo 0x1d6b > idVendor # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadget
echo 0x0100 > bcdDevice # v1.0.0
echo 0x0200 > bcdUSB # USB2
echo "0123456789abcdef" > strings/0x409/serialnumber
echo "USBArmory" > strings/0x409/manufacturer
echo "USBArmory Gadget" > strings/0x409/product
echo "Conf1" > configs/c.1/strings/0x409/configuration
echo 120 > configs/c.1/MaxPower

# Activate gadgets
echo ci_hdrc.0 > UDC
