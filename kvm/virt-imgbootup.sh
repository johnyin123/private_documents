#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("0d41d47[2025-01-24T08:56:30+08:00]:virt-imgbootup.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
ARCH=${ARCH:-x86_64}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env ARCH=aarch64 set arch, default x86_64
        env CPU=kvm64 set cpu type, default host
        env NET=e1000e set netcard type, default virtio-net-pci
        env MACHINE=pc set machine(winxp us pc), default q35(x86_64):virt(aarch64)
        env FAKE=EC2/OPENSTACK/NOCLOUD set smibios enum ec2/openstack if no set no enum
                 NOCLOUD:http://169.254.169.254/__dmi.system-uuid__/
        -c|--cpu    <int>     number of cpus (default 1)
        -m|--mem    <int>     mem size MB (default 2048)
        -D|--disk   <file>    disk image (multi disk must same format)
                    nbd:192.0.2.1:30000
                    nbd:unix:/tmp/nbd-socket
                    ssh://user@host:port/path/to/disk.img
                    iscsi://192.0.2.1/iqn.2001-04.com.example/1
                    rbd:cephpool/win2k12r2.raw:conf=/etc/ceph/ceph.conf
                    gluster+tcp://1.2.3.4:24007/testvol/dir/a.img
                    /dev/sda2
        -b|--bridge <br>      host net bridge
        -f|--fmt    <fmt>     disk image format(default auto detect!)
        --simusb    <file>    simulation usb disk(raw format)
        --pci       <pci_bus_addr> passthrough pci bus address(like: 00:1d.0)
        --usb       <VENDOR_ID:PRODUCT_ID> support usb 3.0
                    passthrough host usb device (support multi usb passthrough)
                    lsusb:
                        Bus 001 Device 003: ID 5986:0652 Acer, Inc
                        Bus [hostbus] Device [hostaddr]: ID VENDOR_ID:PRODUCT_ID .....
        --cdrom     <iso>     iso file
                              disk.iso | http://192.168.168.1/disk.iso | ftp...
        --fda       <file>    floppy disk file
        --serial    <tcp port>  serial listen 127.0.0.1:<tcp port>
        --sound     Enable soundhw hda
        --uefi      <file>    uefi bios file
                    x86_64: /usr/share/qemu/OVMF.fd
                    aarch64:/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
                            /usr/share/AAVMF/AAVMF_CODE.fd
                    apt -y install ovmf
                    apt -y install qemu-system-arm qemu-efi-aarch64
        --daemonize run as daemon, with display none
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        I use kernel 6.1.4, transparent_hugepage cause bootup slow or hang
           echo never > /sys/kernel/mm/transparent_hugepage/enabled
        demo nbd-server:
           qemu-nbd -x tpl --port= --bind= -f raw /storage/linux.tpl
           qemu-nbd -x tpl --socket=/tmp/nbd-socket -f raw /storage/linux.tpl
           qemu-nbd -x tpl rbd:cephpool/win2k12r2.raw:conf=/etc/ceph/ceph.conf
           qemu-nbd -x tpl --persistent --fork --pid-file=/tmp/nbd-socket.pid --socket=/tmp/nbd-socket --format=raw tpl/debian.raw
           1.modprobe nbd && nbd-client -N tpl <IP>/-unix <unix_sock>
           2.<you job>
           3.nbd-client -d /dev/nbd0
           OR
           1.modprobe nbd && qemu-nbd -f qcow -c /dev/nbd0 test.qcow2
           2.<you job>
           3.qemu-nbd -d /dev/nbd0

        demo floppy image:
           mkfs.vfat -C "floppy.img" 1440
           mount -o loop -t vfat floppy.img /mnt/floppy
        demo backing file:
           qemu-img create -f qcow2 -b /tpl/debian10.raw -F raw debian.qcow2 20G
           qemu-img convert -c -f qcow2 -O qcow2 input input.compressed
           qemu-img convert -p -n -f raw rbd:libvirt-pool/vda.raw:id=admin:conf=/etc/ceph/armsite.conf:keyring=/etc/ceph/armsite.client.admin.keyring -O raw out.img
        ram disk:
           # # 2G /dev/ram0
           modprobe brd rd_size=$((2*1024*1024)) max_part=1 rd_nr=1
           rmmod brd
EOF
    exit 1
}

main() {
    local ncpu=1 mem=2048 disk=() bridge=() fmt="" cdrom="" floppy="" usb=() simusb=() pci_bus_addr=() daemonize=no serial=""
    local vmuuid=$(uuid)
    local ec2_serial="ec2${vmuuid:3}"
    local EC2="serial=${ec2_serial},uuid=${ec2_serial}"
    local OPENSTACK="product=OpenStack Compute"
    local NOCLOUD="serial=ds=nocloud;s=http://169.254.169.254/__dmi.system-uuid__/,uuid=${vmuuid}"
    FAKE="${FAKE:-}"
    [ "${FAKE:-x}" == "EC2" ] && FAKE=${EC2}
    [ "${FAKE:-x}" == "OPENSTACK" ] && FAKE=${OPENSTACK}
    [ "${FAKE:-x}" == "NOCLOUD" ] && FAKE=${NOCLOUD}
    local options=(
        "-nodefaults"
        "-no-user-config"
        "-boot" "menu=on"
        "-monitor" "vc"
        "-smbios" "type=1,manufacturer=JohnYin,version=0.9${FAKE:+,${FAKE}}"
    )
    case "${ARCH}" in
        x86_64)   options+=(
            "-enable-kvm"
            "-vga" "qxl"
            "-global" "qxl-vga.vram_size=67108864"
            "-usb"
            "-device" "usb-tablet,bus=usb-bus.0"
            "-device" "nec-usb-xhci,id=xhci"
            )
            MACHINE=${MACHINE:-q35}
            CPU=${CPU:-host}
            ;;
        aarch64)  options+=(
            "-display" "none"
            )
            serial=9999;
            MACHINE=${MACHINE:-virt}
            CPU=${CPU:-"max"}
            ;;
        *)        exit_msg "Unknow arch : ${ARCH}";;
    esac

    local opt_short="c:m:D:b:f:"
    local opt_long="cpu:,mem:,disk:,bridge:,fmt:,cdrom:,fda:,serial:,usb:,simusb:,pci:,sound,daemonize,uefi:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --cpu)     shift; ncpu=${1}; shift;;
            -m | --mem)     shift; mem=${1}; shift;;
            -D | --disk)    shift; disk+=("${1}"); shift;;
            -b | --bridge)  shift; bridge+=("${1}"); shift;;
            -f | --fmt)     shift; fmt=${1}; shift;;
            --usb)          shift; usb+=("${1}"); shift;;
            --simusb)       shift; simusb+=("${1}"); shift;;
            --pci)          shift; pci_bus_addr+=("${1}"); shift;;
            --cdrom)        shift; cdrom=${1}; shift;;
            --fda)          shift; floppy=${1}; shift;;
            --serial)       shift; serial=${1}; shift;;
            --sound)        shift; options+=("-soundhw" "hda");;
            --uefi)         shift; options+=("-bios" "${1}"); shift;;
            --daemonize)    shift; daemonize=yes;;
            # ln -s /home/johnyin/.config/pulse/cookie
            # options+=("-device" "intel-hda")
            # options+=("-device" "hda-duplex,audiodev=snd0")
            # options+=("-audiodev" "pa,id=snd0,server=/run/user/1000/pulse/native")
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
    [ -z "${serial}" ] || {
        options+=("-serial" "telnet:127.0.0.1:${serial},server,nowait")
        info_msg "Serial: tcp:127.0.0.1:${serial}\n"
    }
    is_user_root || exit_msg "root need\n"
    require qemu-system-x86_64 grep sed awk modprobe lspci hexdump
    [ "$(array_size disk)" -gt "0" ] || warn_msg "no disk image!!"
    #file_exists "${disk}" || usage "disk nofound"
    options+=("-machine" "${MACHINE}")
    options+=("-cpu" "${CPU}")
    options+=("-smp" "${ncpu}")
    options+=("-m" "${mem}")
    str_equal "${daemonize:-no}" "yes" && options+=("-daemonize" "-display" "none") || options+=("-monitor" "stdio")
    local _u= _id=0
    for _u in "${bridge[@]}"; do
        bridge_exists "${_u}" || usage "bridge (${_u}) nofound"
        directory_exists /etc/qemu/ || try mkdir -p /etc/qemu/
        grep -q "\s*allow\s*all" /etc/qemu/bridge.conf 2>/dev/null || {
            try "echo 'allow all' >> /etc/qemu/bridge.conf"
            try chmod 640 /etc/qemu/bridge.conf
        }
        options+=("-netdev" "bridge,br=${_u},id=net${_id}")
        local _mac=52:54:$(printf "%02x" ${_id})$(hexdump -v -n3 -e '/1 ":%02X"' /dev/urandom)
        # 00:12:1e: Juniper Networks.
        # 00:19:06: Cisco Systems, Inc.
        # 00:1d:60: ASUSTek COMPUTER INC.
        # 52:54:00: Realtek.
        # 08:00:27: PCS Systemtechnik GmbH.
        # openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//'
        # date | md5sum | sed -r 's/(..){3}/\1:/g;s/\s+-$//'
        #echo $FQDN|md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/'
        # printf -v _mac "52:54:%02x:%02x:%02x:%02x" $(( $RANDOM & 0xff)) $(( $RANDOM & 0xff )) $(( $RANDOM & 0xff)) $(( $RANDOM & 0xff ))
        options+=("-device" "${NET:-virtio-net-pci},netdev=net${_id},mac=${_mac}")
        let _id+=1
    done
    _id=0
    for _u in "${disk[@]}"; do
        local _fmt=${fmt:-$(qemu-img info --output=json ${_u} | json_config_default ".format" "raw")}
        options+=("-drive" "file=${_u},index=${_id},cache=none,aio=native,if=virtio,format=${_fmt}")
        let _id+=1
    done
    for _u in "${simusb[@]}"; do
        options+=("-drive" "if=none,id=usbstick,file=${_u},format=raw")
        options+=("-device" "usb-storage,bus=xhci.0,drive=usbstick")
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
        try lspci -nnk -s ${_u} | vinfo_msg
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
    # TODO: https://wiki.archlinux.org/title/Intel_GVT-g

    # #Create a named pipe
    # mkfifo /tmp/guest.in /tmp/guest.out
    # # Start QEMU
    # # redirects a guest's output to a /tmp/guest.out and allows to send input from host to guest via /tmp/guest.in.
    # qemu-system-x86_64 -serial pipe:/tmp/guest
    #
    # # Take an output from the guest
    # cat /tmp/guest.out
    # # Send a command to the guest
    # printf "root\n" > /tmp/guest.in
    # # Wait until some string
    # while read line; do
    #   echo "${line}"
    #   if [[ ${line} == *"Secure Shell server: sshd"* ]]; then
    #     break;
    #   fi
    # done < /tmp/quest.out
    # try qemu-system-x86_64 "${options[@]}" \
    #     ${cdrom:+-cdrom ${cdrom}} ${floppy:+-fda ${floppy}}

    defined DRYRUN && {
        blue>&2 "DRYRUN: "
        purple>&2 "%s\n" "qemu-system-${ARCH} ${options[*]} ${cdrom:+-cdrom ${cdrom}} ${floppy:+-fda ${floppy}}"
        return 0
    }
    info_msg "start ${ARCH} vm ......\n"
    set -- "${options[@]}" ${cdrom:+-cdrom ${cdrom}} ${floppy:+-fda ${floppy}}
    exec qemu-system-${ARCH} "$@"
}
auto_su "$@"
main "$@"
