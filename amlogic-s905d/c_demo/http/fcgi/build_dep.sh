#!/usr/bin/env bash
#readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly DIRNAME=`pwd`
MYCROSS=${MYCROSS:-}  # x86_64-w64-mingw32 / i686-w64-mingw32 / aarch64-linux-gnu
WIN_TGT=linux-x86_64
[ "${MYCROSS:-}" == "i686-w64-mingw32" ] && { WIN_TGT=mingw; }
[ "${MYCROSS:-}" == "x86_64-w64-mingw32" ] && { WIN_TGT=mingw64; }
[ "${MYCROSS:-}" == "aarch64-linux-gnu" ] && WIN_TGT=linux-aarch64
MYLIB_DEPS=${DIRNAME}/mylibs.${WIN_TGT}
[ -d "${MYLIB_DEPS}" ] && { echo "${MYLIB_DEPS} exists!"; exit 1; }

(cd fcgi2 && { make distclean||true; } && ./autogen.sh && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} --prefix=${MYLIB_DEPS} \
    CFLAGS=-Wunused-const-variable \
    --with-pic --enable-static=yes --enable-shared=no \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { echo  'error~~fcgi2'; exit 1; }
