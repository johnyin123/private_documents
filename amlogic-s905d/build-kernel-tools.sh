#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

KERVERSION="$(make kernelversion)"
export ROOTFS=${1:-${DIRNAME}/mytool-${KERVERSION}-$(date '+%Y%m%d%H%M%S')}

export LIB_ROOTFS=${DIRNAME}/mychroot-aarch64

cat <<EOF
host: apt -y install libwrap0 libtool automake autoconf pkg-config
# # get target dev package, and extract it.(aarch664)
apt download libudev-dev libudev, dpkg -x ..deb ${LIB_ROOTFS}
apt download libelf-dev zlib1g-dev"
EOF
[ -d "${LIB_ROOTFS}" ] || { echo "${LIB_ROOTFS} for aarch64 library NOT EXIST!"; exit 1;}

# [ -e "${DIRNAME}/gcc-aarch64" ] && {
#     export PATH=${DIRNAME}/gcc-aarch64/bin/:$PATH
#     export MY_CROSS_COMPILE=aarch64-linux
# } || {
    # apt -y install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu bison flex libelf-dev libssl-dev
    # apt -y install pahole -t bullseye-backports
    export MY_CROSS_COMPILE=aarch64-linux-gnu
#}
export ARCH=arm64

build_perf () {
    # apt install libdw-dev libunwind-dev systemtap-sdt-dev libslang2-dev libperl-dev python3-dev libcap-dev libnuma-dev libbabeltrace-dev libpfm4-dev libtraceevent-dev
    export CROSS_COMPILE=${MY_CROSS_COMPILE}-
    make V=1 -j$(nproc) LDFLAGS=-L"${LIB_ROOTFS}/usr/lib/aarch64-linux-gnu/" -C "${DIRNAME}/tools/perf"
    prefix=/usr make DESTDIR=${ROOTFS} V=1 -j$(nproc) -C "${DIRNAME}/tools/perf" install
}

build_bpftool () {
    export CROSS_COMPILE=${MY_CROSS_COMPILE}-
    echo "apt -y install libelf-dev zlib1g-dev"
    make V=1 -j$(nproc) -C "${DIRNAME}/tools/bpf/bpftool" clean && make V=1 -j$(nproc) LDFLAGS=-L"${LIB_ROOTFS}/usr/lib/aarch64-linux-gnu/" -C "${DIRNAME}/tools/bpf/bpftool"
    prefix=/usr make DESTDIR=${ROOTFS} V=1 -j$(nproc) -C "${DIRNAME}/tools/bpf/bpftool" install
}

build_usbip () {
    echo "apt -y install libudev-dev"
    $(cd ${DIRNAME}/tools/usb/usbip && ./cleanup.sh && ./autogen.sh && LDFLAGS=-L${LIB_ROOTFS}/usr/lib/aarch64-linux-gnu/ ./configure --host=${MY_CROSS_COMPILE} --enable-shared=no --prefix=/usr --with-usbids-dir=/usr/share/misc/)
    make V=1 -j$(nproc) -C ${DIRNAME}/tools/usb/usbip
    make DESTDIR=${ROOTFS} V=1 -j$(nproc) -C ${DIRNAME}/tools/usb/usbip install
}
build_bpftool
build_usbip
${MY_CROSS_COMPILE}-strip ${ROOTFS}/usr/sbin/bpftool
${MY_CROSS_COMPILE}-strip ${ROOTFS}/usr/sbin/usbip
${MY_CROSS_COMPILE}-strip ${ROOTFS}/usr/sbin/usbipd
echo 'fpm --package `pwd` --architecture aarch64 -s dir -t deb -C bpf --name bpftool --version 6.10.3 --iteration 1 --description "bpftool" .'
