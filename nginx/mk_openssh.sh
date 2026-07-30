#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

OPENSSH_DIR="${1:? MUSL=1/MYARM=1 $0 <openssh_dir> [lib_dir]}"
MYLIB_DEPS=${2:-${DIRNAME}/mylibs}
OPENSSH_DIR="$(readlink -f "${OPENSSH_DIR}")"
MYLIB_DEPS="$(readlink -f "${MYLIB_DEPS}")"

export CPPFLAGS="-I${MYLIB_DEPS}/include -fPIC"
export CFLAGS="-I${MYLIB_DEPS}/include -fPIC"
export LDFLAGS="-L${MYLIB_DEPS}/lib"
export LDFLAGS="${MUSL:+-static -static-libgcc} ${LDFLAGS}"

cd ${OPENSSH_DIR} && { make distclean &>/dev/null||true; } && \
    CC=${MYARM:+aarch64-linux-gnu-}${MUSL:+musl-}gcc \
    ./configure --prefix="/opt/openssh" \
        LIBS="-lpthread" \
        --with-privsep-user=nobody \
        --with-privsep-path="/opt/openssh/var/empty" \
    && make && make install DESTDIR=${DIRNAME}/mysshd/
