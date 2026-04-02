#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
MYCROSS=${MYCROSS:-}  # x86_64-w64-mingw32 / i686-w64-mingw32 / aarch64-linux-gnu
WIN_TGT=linux-x86_64
[ "${MYCROSS:-}" == "i686-w64-mingw32" ] && { WIN_TGT=mingw; MYCURL_LIB="-lws2_32 -lgdi32 -lcrypt32"; }
[ "${MYCROSS:-}" == "x86_64-w64-mingw32" ] && { WIN_TGT=mingw64; MYCURL_LIB="-lws2_32 -lgdi32 -lcrypt32"; }
[ "${MYCROSS:-}" == "aarch64-linux-gnu" ] && WIN_TGT=linux-aarch64
MYLIB_DEPS=${DIRNAME}/mylibs.${WIN_TGT}
# MYLIB_DEPS=${DIRNAME}/mylibs
[ -d "${MYLIB_DEPS}" ] && { echo "${MYLIB_DEPS} exists!"; exit 1; }
(cd openssl && { make distclean||true; } && ./Configure ${MYCROSS:+${WIN_TGT} --cross-compile-prefix=${MYCROSS}-} \
    --prefix=${MYLIB_DEPS} no-zstd no-zlib \
    no-shared no-threads no-tests no-legacy no-apps no-docs \
    && perl configdata.pm --dump \
    && make -j "$(nproc)" build_libs \
    && make -j "$(nproc)" install_sw LIBDIR=lib) || { echo  'error~~openssl'; exit 1; }
(cd curl && { make distclean||true; } && ./configure ${MYCURL_LIB:+LIBS="${MYCURL_LIB}"} CPPFLAGS="-DCURL_STATICLIB" ${MYCROSS:+--host=${MYCROSS}} \
    --with-pic=yes --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes \
    --with-openssl=${MYLIB_DEPS} \
    --without-libidn2 \
    --without-libpsl --without-zlib --without-brotli --without-zstd  \
    --without-ldap --disable-ldap --disable-ldaps \
    --disable-alt-svc \
    --disable-docs \
    --disable-ipfs \
    --disable-rtsp && make -j "$(nproc)" && make -j "$(nproc)" install) || { echo  'error~~libcurl'; exit 1; }
unset CPPFLAGS
unset LIBS

(cd expat && { make distclean||true; } && ./configure ${MYCROSS:+--host=${MYCROSS}} --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --enable-pic=yes \
    --without-xmlwf --without-examples --without-tests \
    --without-docbook && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { echo  'error~~expat'; exit 1; }

(cd libiconv && { make distclean||true; } && ./configure ${MYCROSS:+--host=${MYCROSS}} --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --enable-pic=yes \
    --disable-largefile --disable-rpath \
    --disable-nls && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { echo  'error~~iconv'; exit 1; }
