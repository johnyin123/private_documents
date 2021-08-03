#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("virt-imgbootup.sh - 3c370c6 - 2021-08-02T10:39:09+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--cpu    <int>     number of cpus (default 1)
        -m|--mem    <int>     mem size MB (default 2048)
        -D|--disk   <file> *  disk image (multi disk must same format)
                    nbd:192.0.2.1:30000
                    nbd:unix:/tmp/nbd-socket
                    ssh://user@host/path/to/disk.img
                    iscsi://192.0.2.1/iqn.2001-04.com.example/1
                    /dev/sda2
        -b|--bridge <br>      host net bridge
        -f|--fmt    <fmt>     disk image format(default raw)
        --simusb    <file>    simulation usb disk(raw format)
        --pci       <pci_bus_addr> passthrough pci bus address(like: 00:1d.0)
        -usb        <VENDOR_ID:PRODUCT_ID> support usb 3.0
                    passthrough host usb device (support multi usb passthrough)
                    lsusb:
                        Bus 001 Device 003: ID 5986:0652 Acer, Inc
                        Bus [hostbus] Device [hostaddr]: ID VENDOR_ID:PRODUCT_ID .....
        --cdrom     <iso>     iso file
        --fda       <file>    floppy disk file
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        demo nbd-server:
           qemu-nbd -f raw /storage/linux.tpl
           qemu-nbd rbd:cephpool/win2k12r2.raw:conf=/etc/ceph/ceph.conf
        demo floppy image:
           mkfs.vfat -C "floppy.img" 1440
           mount -o loop -t vfat floppy.img /mnt/floppy
        demo backing file:
           qemu-img create -f qcow2 -b /tpl/debian10.raw -F raw debian.qcow2 20G
EOF
    exit 1
}

main() {
    local options=(
        "-enable-kvm"
        "-vga" "qxl"
        "-global" "qxl-vga.vram_size=67108864" 
        "-nodefaults"
        "-no-user-config"
        "-usb" "-device usb-tablet,bus=usb-bus.0" "-device nec-usb-xhci,id=xhci"
        "-boot" "menu=on"
        "-M" "q35"
    )

    local cpu=1 mem=2048 disk=() bridge= fmt=raw cdrom= floppy= usb=() simusb=() pci_bus_addr=()
    local opt_short="c:m:D:b:f:"
    local opt_long="cpu:,mem:,disk:,bridge:,fmt:,cdrom:,fda:,usb:,simusb:,pci:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --cpu)     shift; cpu=${1}; shift;;
            -m | --mem)     shift; mem=${1}; shift;;
            -D | --disk)    shift; disk+=("${1}"); shift;;
            -b | --bridge)  shift; bridge=${1}; shift;;
            -f | --fmt)     shift; fmt=${1}; shift;;
            --usb)          shift; usb+=("${1}"); shift;;
            --simusb)       shift; simusb+=("${1}"); shift;;
            --pci)          shift; pci_bus_addr+=("${1}"); shift;;
            --cdrom)        shift; cdrom=${1}; shift;;
            --fda)          shift; floppy=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    is_user_root || exit_msg "root need\n"
    require qemu-system-x86_64 grep sed awk modprobe lspci
    [ "$(array_size disk)" -gt "0" ] || usage "disk image ?"
    #file_exists "${disk}" || usage "disk nofound"
    options+=("-cpu" "kvm64")
    options+=("-monitor" "vc")
    options+=("-smp" "${cpu}")
    options+=("-m" "${mem}")
    [ -z ${bridge} ] || {
        bridge_exists "${bridge}" || usage "bridge nofound"
        directory_exists /etc/qemu/ || try mkdir -p /etc/qemu/
        grep "\s*allow\s*all" /etc/qemu/bridge.conf || {
            try "echo 'allow all' >> /etc/qemu/bridge.conf"
            try chmod 640 /etc/qemu/bridge.conf
        }
        options+=("-netdev" "bridge,br=${bridge},id=net0")
        options+=("-device" "virtio-net-pci,netdev=net0,mac=${MAC:-52:54:00:11:22:33}")
    }
    local disk_id=0
    for _u in "${disk[@]}"; do
        options+=("-drive" "file=${_u},index=${disk_id},cache=none,aio=native,if=virtio,format=${fmt}")
        let disk_id+=1
    done
    for _u in "${simusb[@]}"; do
        options+=("-drive" "if=none,id=usbstick,file=${_u},format=raw")
        options+=("-device usb-storage,bus=xhci.0,drive=usbstick")
    done
    for _u in "${usb[@]}"; do
        #local _bus=$(lsusb | grep "${_u}" | awk '{ print $2 }' | sed 's/^0*//')
        #local _dev=$(lsusb | grep "${_u}" | awk '{ gsub(":","",$4); print $4 }' | sed 's/^0*//')
        #local _port=$(lsusb -t \
        #    | sed -n -e '/Bus 0*'"${_bus}"'/,/Bus/p' \
        #    | sed -e '1d' -e '$d' \
        #    | sed -n '/Dev 0*'"${_dev}"'/p' \
        #    | sed -n '1p' \
        #    | sed 's/^.*Port \([0-9]\).*$/\1/g')
        ##options+=("-device" "usb-host,hostbus=${_bus},hostaddr=${_dev}")
        #options+=("-device" "usb-host,hostbus=${_bus},hostport=${_port}")
        # usb passthrough need -M q35
        options+=("-device" "usb-host,bus=xhci.0,vendorid=0x${_u%%:*},productid=0x${_u##*:}")
    done
    for _u in "${pci_bus_addr[@]}"; do
        # GPU passthrough:
        modprobe -i vfio-pci
        try lspci -nnk  -s ${_u} | vinfo_msg
        local vendor=$(cat /sys/bus/pci/devices/0000:${_u}/vendor)
        local device=$(cat /sys/bus/pci/devices/0000:${_u}/device)
        if [ -e /sys/bus/pci/devices/0000:${_u}/driver ]; then
            local iommu_group=$(readlink -f /sys/bus/pci/devices/0000:${_u}/iommu_group)
            iommu_group=${iommu_group##*/}
            #/sys/kernel/iommu_groups/${_i}/devices/
            for _i in /sys/bus/pci/devices/0000:${_u}/iommu_group/devices/*
            do
                _i=${_i##*/}
                info_msg "pci unbind ${_i} in iommu_group [${iommu_group}]\n"
                echo "${_i}" > /sys/bus/pci/devices/${_i}/driver/unbind
            done
            echo "0000:${_u}" > /sys/bus/pci/drivers/vfio-pci/bind
        fi
        info_msg "pci bind ${_u} to vfio-pci\n"
        echo ${vendor} ${device} > /sys/bus/pci/drivers/vfio-pci/new_id
        # For VMs with an Nvidia GPU attached, you must add the following
        # options to bypass the Nvidia driver's virtualization check.
        #   -cpu kvm=off,hv_vendor_id=null
        #   -device vfio-pci,host=00:00.0,multifunction=on,x-vga=on -display none -vga none
        options+=("-device" "vfio-pci,host=${_u}")
    done
    try qemu-system-x86_64 "${options[@]}" \
        ${cdrom:+-cdrom ${cdrom}} ${floppy:+-fda ${floppy}}
}
main "$@"
