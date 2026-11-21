DISK_IMG=${1:?device/image <fs> <gpt/msdos>??}
FS=${2:-xfs}
PART=${3:-gpt}
echo "GPT ${PART}: ${DISK_IMG} ${FS} command"
ROOT=72
HOME=64
[ "${PART:-x}" == "gpt" ] && {
    cat <<EOF | sed "s/\s*#.*$//g"
parted -s ${DISK_IMG} "mklabel gpt"
parted -s ${DISK_IMG} "mkpart primary fat32 1M 128M"
parted -s ${DISK_IMG} "mkpart primary ${FS} 128M ${ROOT}G"           #rootfs
parted -s ${DISK_IMG} "mkpart primary ${FS} ${ROOT}G $((${ROOT}+${HOME}))G"    #home
parted -s ${DISK_IMG} "mkpart primary ${FS} $((${ROOT}+${HOME}))G %100"   #data
parted -s ${DISK_IMG} "set 1 boot on"
EOF
} || {
    cat <<EOF | sed "s/\s*#.*$//g"
parted -s ${DISK_IMG} "mklabel msdos"
parted -s ${DISK_IMG} "mkpart primary ${FS} 1M ${ROOT}G"           #rootfs
parted -s ${DISK_IMG} "mkpart primary ${FS} ${ROOT}G $((${ROOT}+${HOME}))G"    #home
parted -s ${DISK_IMG} "mkpart primary ${FS} $((${ROOT}+${HOME}))G %100"   #data
parted -s ${DISK_IMG} "set 1 boot on"
EOF
}
