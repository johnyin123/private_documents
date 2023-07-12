iso() {
    ISO_FILENAME="${ROOTFS_DIR}.iso"
    CDROM_DIR="${ROOTFS_DIR}-cdrom"

    mkdir -pv ${CDROM_DIR}/{live,boot/grub,EFI/BOOT}
    cp -v ${ROOTFS_DIR}/boot/vmlinuz ${CDROM_DIR}/live/vmlinuz
    cp -v ${ROOTFS_DIR}/boot/initrd.img ${CDROM_DIR}/live/initrd.lz

    echo "---> mksquash"
    mksquashfs ${ROOTFS_DIR} ${CDROM_DIR}/live/filesystem.squashfs -quiet # -comp xz -no-progress

    cat >${CDROM_DIR}/boot/grub/grub.cfg <<EOF
set timeout=30
set default="0"
insmod all_video
menuentry "Debian GNU/Linux Live" {
    linux  /live/${vmlinuz##*/} boot=live live-media-path=/live/ toram=filesystem.squashfs net.ifnames=0 biosdevname=0 console=ttyS0,115200n8 console=tty1
    initrd /live/${initrd##*/}
}
EOF
    if [ "${VK_ARCH}" = "arm64" ]; then
        EFINAME="bootaa64.efi"
    elif [ "${VK_ARCH}" = "amd64" ]; then
        EFINAME="bootx64.efi"
    fi
    # efi
    if [ -f "${CURRENT_DIR}/${EFINAME}" ]; then
        cp -v ${CURRENT_DIR}/${EFINAME} ${CDROM_DIR}/EFI/BOOT/${EFINAME}
    fi
    dd if=/dev/zero of=${CDROM_DIR}/boot/grub/efi.img bs=1M count=10
    mkfs.vfat ${CDROM_DIR}/boot/grub/efi.img
    mmd -i ${CDROM_DIR}/boot/grub/efi.img efi efi/boot
    mcopy -i ${CDROM_DIR}/boot/grub/efi.img ${CDROM_DIR}/EFI/BOOT/${EFINAME} ::efi/boot/
    mkisofs -input-charset utf-8 -J -r -V LiveLinux -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -o ${ISO_FILENAME} ${CDROM_DIR}
}

