#!/usr/bin/env bash
create_zram_drive () {
    if [ ! -d "/sys/class/zram-control" ]; then
        modprobe zram
        RAM_DEV='0'
    else
        RAM_DEV=$(cat /sys/class/zram-control/hot_add)
    fi
    echo "$COMP_ALG" > "/sys/block/zram${RAM_DEV}/comp_algorithm"
    echo "$LOG_DISK_SIZE" > "/sys/block/zram${RAM_DEV}/disksize"
    echo "$SIZE" > "/sys/block/zram${RAM_DEV}/mem_limit"
    mke2fs -t ext4 "/dev/zram${RAM_DEV}"
}
