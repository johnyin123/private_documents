#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

cat <<EOF
# # TODO: cross compile failed link depends libs: udev/libz/libelf.........
# # so: in chroot env, build it!
apt -y install libwrap0 libtool automake autoconf pkg-config
EOF

build_bpftool () {
    echo "apt -y install libelf-dev zlib1g-dev"
    make V=1 -j$(nproc) -C "${DIRNAME}/tools/bpf/bpftool" clean && make V=1 -j$(nproc) -C "${DIRNAME}/tools/bpf/bpftool"
    make DESTDIR=${DIRNAME}/mytool V=1 -j$(nproc) -C ${DIRNAME}/tools/usb/usbip install
}

build_usbip () {
    echo "apt -y install libudev-dev"
    $(cd ${DIRNAME}/tools/usb/usbip && ./cleanup.sh && ./autogen.sh && ./configure --prefix=/usr)
    make V=1 -j$(nproc) -C ${DIRNAME}/tools/usb/usbip
    make DESTDIR=${DIRNAME}/mytool V=1 -j$(nproc) -C ${DIRNAME}/tools/usb/usbip install
}
