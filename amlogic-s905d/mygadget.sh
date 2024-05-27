#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("86417ea[2024-05-24T16:40:25+08:00]:mygadget.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
readonly GADGET="/sys/kernel/config/usb_gadget/g1"
readonly SEQ=1
readonly LANG_ID="0x409"   # en_US
readonly SERIAL_NO="Phicomm n1 s905d"
readonly MANUFACTURER="My USB Gadget Foundation"
readonly PRODUCT="JohnYin"
readonly DESCRIPTION="My USB Gadget configuration"

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--create     * <func>   usb gadget type, storage|serial|network|hid
        -D|--destroy               destroy gadget
        --node            <str>    usb nodename, default USB0
        --store           <str>    usb disk storage file name
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

init_end() {
    info_msg "Done creating functions and configs, enabling UDC\n"
    # echo ci_hdrc.0 > "${GADGET}/UDC"
    ls /sys/class/udc | try tee "${GADGET}/UDC"
}

init_start() {
    [ -d "${GADGET}" ] && exit_msg "${GADGET} exists!!!\n"
    info_msg "init usb gadget configfs ${GADGET}\n"
    try mkdir -p "${GADGET}"
    echo 0x1d6b | try tee "${GADGET}/idVendor"  # Linux Foundation
    echo 0x0104 | try tee "${GADGET}/idProduct" # Multifunction Composite Gadget
    echo 0x0100 | try tee "${GADGET}/bcdDevice" # v1.0.0
    echo 0x0200 | try tee "${GADGET}/bcdUSB"    # USB2
    echo 0xEF   | try tee "${GADGET}/bDeviceClass"
    echo 0x02   | try tee "${GADGET}/bDeviceSubClass"
    echo 0x01   | try tee "${GADGET}/bDeviceProtocol"

    try mkdir -p "${GADGET}/os_desc"
    echo 1       | try tee "${GADGET}/os_desc/use"
    echo 0xcd    | try tee "${GADGET}/os_desc/b_vendor_code"
    echo MSFT100 | try tee "${GADGET}/os_desc/qw_sign"

    try mkdir -p "${GADGET}/strings/${LANG_ID}"
    echo "${SERIAL_NO}"    | try tee "${GADGET}/strings/${LANG_ID}/serialnumber"
    echo "${MANUFACTURER}" | try tee "${GADGET}/strings/${LANG_ID}/manufacturer"
    echo "${PRODUCT}"      | try tee "${GADGET}/strings/${LANG_ID}/product"

    try mkdir -p "${GADGET}/configs/c.${SEQ}/strings/${LANG_ID}"
    echo "${DESCRIPTION}" | try tee "${GADGET}/configs/c.${SEQ}/strings/${LANG_ID}/configuration"
    try ln -s "${GADGET}/configs/c.${SEQ}" "${GADGET}/os_desc"
    echo 250 | try tee "${GADGET}/configs/c.${SEQ}/MaxPower"
}

destroy() {
    info_msg "Destroy usb gadget\n"
    [ -d "${GADGET}" ] || return 0
    info_msg "Disabling the gadget\n"
    echo "" | try tee ${GADGET}/UDC 2>/dev/null || true
    try rm -f ${GADGET}/os_desc/c.${SEQ}
    info_msg "Removing strings from configurations\n"
    for dir in ${GADGET}/configs/*/strings/*; do
        [ -d ${dir} ] && try rmdir ${dir}
    done
    info_msg "Removing functions from configurations\n"
    for func in ${GADGET}/configs/*.*/*.*; do
        [ -e ${func} ] && try rm ${func}
    done
    info_msg "Removing configurations\n"
    for conf in ${GADGET}/configs/*; do
        [ -d ${conf} ] && try rmdir ${conf}
    done
    info_msg "Removing functions\n"
    for func in ${GADGET}/functions/*.*; do
        [ -d ${func} ] && try rmdir ${func}
    done
    info_msg "Removing strings\n"
    for str in ${GADGET}/strings/*; do
        [ -d ${str} ] && try rmdir ${str}
    done
    info_msg "Removing gadget\n"
    rmdir ${GADGET}
    info_msg "Done removing gadget\n"
    [ -d "${GADGET}" ] && { error_msg "Gadget still exists... ${GADGET}\n"; return 1; }
    return 0
}

create_storage() {
    local usb_file=${1}
    local node=${2:-"USB0"}
    info_msg "configure gadget storage, ${usb_file} => ${node}\n"
    try mkdir -p "${GADGET}/functions/mass_storage.${node}"
    echo 1 | try tee "${GADGET}/functions/mass_storage.${node}/stall"
    echo 0 | try tee "${GADGET}/functions/mass_storage.${node}/lun.0/cdrom"
    echo 0 | try tee "${GADGET}/functions/mass_storage.${node}/lun.0/ro"
    echo 0 | try tee "${GADGET}/functions/mass_storage.${node}/lun.0/nofua"
    echo "${usb_file}" | try tee "${GADGET}/functions/mass_storage.${node}/lun.0/file"
    try ln -s "${GADGET}/functions/mass_storage.${node}" "${GADGET}/configs/c.${SEQ}/"
}

create_serial() {
    local node=${1:-"USB0"}
    info_msg "configure gadget serial ${node}\n"
    try mkdir -p "${GADGET}/functions/acm.${node}"
    try ln -s "${GADGET}/functions/acm.${node}" "${GADGET}/configs/c.${SEQ}/"
    info_msg "start USB serial for console: systemctl start serial-getty@ttyGS0.service\n"
}
# mkdir -p /dev/usb-ffs/adb
# mount -o uid=2000,gid=2000 -t functionfs adb /dev/usb-ffs/adb
# export service_adb_tcp_port=5555
# start-stop-daemon --start --oknodo --make-pidfile --pidfile /var/run/adbd.pid --startas /usr/bin/adbd --background
create_ethernet() {
    # Ethernet device
    #  adbd GADGET="ffs.adb"
    #  usbnet GADGET="ecm.usb0"
    ###
    local dev_eth_addr=${1}
    local host_eth_addr=${2}
    local node=${3:-"USB0"}
    info_msg "configure gadget ethernet ${node}\n"
    try mkdir "${GADGET}/functions/ecm.${node}"
    echo "${dev_eth_addr}" | try tee "${GADGET}/functions/ecm.usb0/dev_addr"
    echo "${host_eth_addr}" | try tee "${GADGET}/functions/ecm.usb0/host_addr"
    try ln -s "${GADGET}/functions/ecm.${node}" "${GADGET}/configs/c.${SEQ}/"
}

create_network() {
    local node=${1:-"USB0"}
    info_msg "configure gadget network Microsoft Ethernet over USB ${node}\n"
    try mkdir -p "${GADGET}/functions/rndis.${node}/os_desc/interface.rndis"
    echo RNDIS   | try tee "${GADGET}/functions/rndis.${node}/os_desc/interface.rndis/compatible_id"
    echo 5162001 | try tee "${GADGET}/functions/rndis.${node}/os_desc/interface.rndis/sub_compatible_id"
    try ln -s "${GADGET}/functions/rndis.${node}" "${GADGET}/configs/c.${SEQ}/"
}

create_hid() {
    local node=${1:-"USB0"}
    info_msg "configure gadget hid ${node}\n"
    try mkdir -p "${GADGET}/functions/hid.${node}"
    echo 1 | try tee "${GADGET}/functions/hid.${node}/protocol"
    echo 1 | try tee "${GADGET}/functions/hid.${node}/subclass"
    echo 8 | try tee "${GADGET}/functions/hid.${node}/report_length"
    echo -ne "\\x05\\x01\\x09\\x06\\xa1\\x01\\x05\\x07\\x19\\xe0\\x29\\xe7\\x15\\x00\\x25\\x01\\x75\\x01\\x95\\x08\\x81\\x02\\x95\\x01\\x75\\x08\\x81\\x03\\x95\\x05\\x75\\x01\\x05\\x08\\x19\\x01\\x29\\x05\\x91\\x02\\x95\\x01\\x75\\x03\\x91\\x03\\x95\\x06\\x75\\x08\\x15\\x00\\x25\\x65\\x05\\x07\\x19\\x00\\x29\\x65\\x81\\x00\\xc0" | try tee "${GADGET}/functions/hid.${node}/report_desc"
    try ln -s "${GADGET}/functions/hid.${node}" "${GADGET}/configs/c.${SEQ}/"
}

main() {
    local create="" store="" node="USB0"
    local opt_short="c:D"
    local opt_long="create:,destroy,node:,store:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --create)  shift; create=${1}; shift;;
            -D | --destroy) shift; destroy; exit 0;;
            --node)         shift; node=${1}; shift;;
            --store)        shift; store="${1}"; shift;;
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
    # [ ! -e "/sys/kernel/config/usb_gadget/$UDC" ] && { modprobe libcomposite; mkdir -p "/sys/kernel/config/usb_gadget/$UDC"; }
    modprobe -q libcomposite || exit_msg "kernel not support libcomposite configfs\n"
    case "${create}" in
        storage)
            file_exists "${store}" || exit_msg "${store} store not exists!!\n"
            init_start
            create_storage "${store}" "${node}"
            init_end
            ;;
        network)
            init_start
            create_network "${node}"
            init_end
            ;;
        serial)
            init_start
            create_serial "${node}"
            init_end
            ;;
        hid)
            init_start
            create_hid "${node}"
            init_end
            ;;
        *) usage "usb gadget type miss";;
    esac
    return 0
}
main "$@"
