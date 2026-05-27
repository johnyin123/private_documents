#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
VERSION+=("initver[2026-05-27T10:36:45+08:00]:build_libgd.sh")
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

MYCROSS=${MYCROSS:-}  # x86_64-w64-mingw32 / i686-w64-mingw32 / aarch64-linux-gnu
WIN_TGT=linux-x86_64
[ "${MYCROSS:-}" == "i686-w64-mingw32" ] && { WIN_TGT=mingw; }
[ "${MYCROSS:-}" == "x86_64-w64-mingw32" ] && { WIN_TGT=mingw64; }
[ "${MYCROSS:-}" == "aarch64-linux-gnu" ] && WIN_TGT=linux-aarch64
[ "${MYCROSS:-}" == "musl" ] && {
    MYCROSS=""
    WIN_TGT=linux-musl
    export CC=musl-gcc
    MYSSL_INC="-DOPENSSL_NO_SECURE_MEMORY -idirafter /usr/include/ -idirafter /usr/include/$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
    MUSL_CFLAGS="-D_FILE_OFFSET_BITS=64"
}
cat <<'EOF' >&2
KTLS=1 ./build_deps.sh [output libdir]
MYCROSS=aarch64-linux-gnu ./build_deps.sh [output libdir]
        i686-w64-mingw32
        x86_64-w64-mingw32
        musl
apt -y install gcc-aarch64-linux-gnu \
               g++-aarch64-linux-gnu \
               gcc-mingw-w64-x86-64 \
               g++-mingw-w64-x86-64 \
               gcc-mingw-w64-i686 \
               g++-mingw-w64-i686 \
               ntldd \
               musl-dev musl-tools
EOF
MYLIB_DEPS=${1:-${DIRNAME}/mylibs.${WIN_TGT}}
[ -d "${MYLIB_DEPS}" ] && MYLIB_DEPS="$(readlink -f "${MYLIB_DEPS}")"
################################################################################
read -n 1 -p "Press any key continue build ..." value
################################################################################

[ -z "${MYCROSS}" ] || {
    case "${MYCROSS}" in
        *aarch64-*linux-*)  _LIBGD_DEP_SYS=Linux;   _LIBGD_DEP_ARCH=arm64;;
        *x86_64-*mingw32*)  _LIBGD_DEP_SYS=Windows; _LIBGD_DEP_ARCH=amd64;;
        *i686-*mingw32*)    _LIBGD_DEP_SYS=Windows; _LIBGD_DEP_ARCH=x86;;
        *)                  echo "---${MYCROSS}---TODO::--${SRC_DIR}---"; exit 1;;
    esac
}
# https://www.libpng.org/pub/png/libpng.html
SRC_DIR=libpng
log "Building ${CC:-} ${SRC_DIR} ....................................."
# ([ -d "${SRC_DIR}" ] && { log "clean ${SRC_DIR}...."; rm -fr ${SRC_DIR}-build &>/dev/null||true; } && \
#     mkdir -p ${SRC_DIR}-build \
#     && cmake ${CC:+-DCMAKE_C_COMPILER=${CC}} ${MYCROSS:+-DCMAKE_SYSTEM_NAME=${_LIBGD_DEP_SYS} -DCMAKE_SYSTEM_PROCESSOR=${_LIBGD_DEP_ARCH} -DCMAKE_C_COMPILER=${MYCROSS}-gcc -DCMAKE_C_COMPILER_TARGET=${MYCROSS}} \
#         -S ${SRC_DIR} -B ${SRC_DIR}-build \
#         --install-prefix ${MYLIB_DEPS} \
#         -DPNG_TESTS=OFF -DPNG_SHARED=OFF -DPNG_STATIC=ON \
#     && cmake --build ${SRC_DIR}-build --target install --config Release)  && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    CPPFLAGS="-I${MYLIB_DEPS}/include" LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS=-fPIC \
    --prefix=${MYLIB_DEPS} \
    --disable-tests --disable-tools \
    --enable-static=yes --enable-shared=no \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

# https://libjpeg-turbo.org/ https://github.com/libjpeg-turbo/libjpeg-turbo
SRC_DIR=libjpeg-turbo
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && { log "clean ${SRC_DIR}...."; rm -fr ${SRC_DIR}-build &>/dev/null||true; } && \
    mkdir -p ${SRC_DIR}-build \
    && cmake ${CC:+-DCMAKE_C_COMPILER=${CC}} ${MYCROSS:+-DCMAKE_SYSTEM_NAME=${_LIBGD_DEP_SYS} -DCMAKE_SYSTEM_PROCESSOR=${_LIBGD_DEP_ARCH} -DCMAKE_C_COMPILER=${MYCROSS}-gcc -DCMAKE_C_COMPILER_TARGET=${MYCROSS}} \
        -S ${SRC_DIR} -B ${SRC_DIR}-build \
        --install-prefix ${MYLIB_DEPS} \
        -DWITH_TOOLS=OFF -DWITH_TESTS=OFF -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
    && cmake --build ${SRC_DIR}-build --target install --config Release)  && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

# https://storage.googleapis.com/downloads.webmproject.org/releases/webp/index.html
SRC_DIR=libwebp
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && { log "clean ${SRC_DIR}...."; rm -fr ${SRC_DIR}-build &>/dev/null||true; } && \
    mkdir -p ${SRC_DIR}-build \
    && cmake ${CC:+-DCMAKE_C_COMPILER=${CC}} ${MYCROSS:+-DCMAKE_SYSTEM_NAME=${_LIBGD_DEP_SYS} -DCMAKE_SYSTEM_PROCESSOR=${_LIBGD_DEP_ARCH} -DCMAKE_C_COMPILER=${MYCROSS}-gcc -DCMAKE_C_COMPILER_TARGET=${MYCROSS}} \
        -S ${SRC_DIR} -B ${SRC_DIR}-build \
        --install-prefix ${MYLIB_DEPS} \
        -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
        -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF \
        -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
    && cmake --build ${SRC_DIR}-build --target install --config Release)  && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

# https://github.com/libgd/libgd/releases
SRC_DIR=libgd
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    PKG_CONFIG_PATH=${MYLIB_DEPS}/lib/pkgconfig/ \
    CC=${MYCROSS:+${MYCROSS}-}gcc \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CPPFLAGS="-I${MYLIB_DEPS}/include" CFLAGS="-fPIC ${MUSL_CFLAGS:-}" LIBS="-lpng -lz" \
    --prefix=${MYLIB_DEPS} \
    --without-freetype --without-raqm --without-fontconfig --without-liq \
    --without-xpm --without-tiff --without-heif --without-avif \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    && make -j "$(nproc)" -C src \
    && make -j "$(nproc)" -C config \
    && make -j "$(nproc)" -C src install-libLTLIBRARIES \
    && make -j "$(nproc)" install-data) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }
