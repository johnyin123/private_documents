DISK_IMG=${1:?device/image??}
FS=${2:-xfs}
echo "GPT part: ${DISK_IMG} ${FS} command"
ROOT=72
HOME=64
cat <<EOF | sed "s/\s*#.*$//g"
parted -s ${DISK_IMG} "mklabel gpt"
parted -s ${DISK_IMG} "mkpart primary fat32 1M 128M"
parted -s ${DISK_IMG} "mkpart primary ${FS} 128M ${ROOT}G"           #rootfs
parted -s ${DISK_IMG} "mkpart primary ${FS} ${ROOT}G $((${ROOT}+${HOME}))G"    #home
parted -s ${DISK_IMG} "mkpart primary ${FS} $((${ROOT}+${HOME}))G %100"   #data
parted -s ${DISK_IMG} "set 1 boot on"
EOF
