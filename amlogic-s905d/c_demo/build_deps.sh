#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
MYLIB_DEPS=${DIRNAME}/mylibs
# MYCROSS=x86_64-w64-mingw32
(cd openssl && make clean && ./Configure ${MYCROSS:+mingw64 --cross-compile-prefix=${MYCROSS}-} \
    --prefix=${MYLIB_DEPS} no-zstd no-zlib \
    no-shared no-threads no-tests no-legacy no-apps no-docs \
    && perl configdata.pm --dump \
    && make -j "$(nproc)" build_libs \
    && make -j "$(nproc)" install_sw LIBDIR=lib) || { echo  'error~~openssl'; exit 1; }
 
(cd expat && ./configure ${MYCROSS:+--host=${MYCROSS}} --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --enable-pic=yes \
    --without-xmlwf --without-examples --without-tests \
    --without-docbook && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { echo  'error~~expat'; exit 1; }

(cd curl && OPENSSL_ENABLED=1 ./configure ${MYCROSS:+--host=${MYCROSS}} --with-pic=yes --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes \
    --with-openssl=${MYLIB_DEPS} \
    --without-libidn2 \
    --without-libpsl --without-zlib --without-brotli --without-zstd  \
    --without-ldap --disable-ldap --disable-ldaps \
    --disable-alt-svc \
    --disable-docs \
    --disable-ipfs \
    --disable-rtsp && make -j "$(nproc)" && make -j "$(nproc)" install) || { echo  'error~~libcurl'; exit 1; }
