#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

[ -e "${DIRNAME}/gcc-aarch64" ] && 
{
    export PATH=${DIRNAME}/gcc-aarch64/bin/:$PATH
    export CROSS_COMPILE=aarch64-linux-
} || {
    # apt -y install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu bison flex libelf-dev libssl-dev
    # apt -y install pahole -t bullseye-backports
    export CROSS_COMPILE=aarch64-linux-gnu-
}
export ARCH=arm64
cat <<EOF
libgtk2.0-dev libglade2-dev
EOF
make gconfig
