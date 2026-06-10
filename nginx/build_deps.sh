#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
VERSION+=("5f106155[2026-06-10T10:44:49+08:00]:build_deps.sh")
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
# case "${MY_CROSS}" in
#   arm*linux*)
#     WIN_TGT=linux-armv4
#     ;;
#   aarch64*linux*)
#     WIN_TGT=linux-aarch64
#     ;;
#   mips64*linux*)
#     WIN_TGT=linux64-mips64
#     ;;
#   mips*linux* | mipsel*linux*)
#     WIN_TGT=linux-mips32
#     ;;
#   x86_64*linux*)
#     WIN_TGT=linux-x86_64
#     ;;
#   i?86*linux*)
#     WIN_TGT=linux-x86
#     ;;
#   s390x*linux*)
#     WIN_TGT=linux64-s390x
#     ;;
#   loongarch64*linux*)
#     WIN_TGT=linux64-loongarch64
#     ;;
#   x86_64*mingw*)
#     WIN_TGT=mingw64
#     ;;
#   i686*mingw*)
#     WIN_TGT=mingw
#     ;;
#   *musl*)
#     WIN_TGT=linux-musl
#     MYCROSS=""
#     export CC=musl-gcc
#     MYSSL_INC="-DOPENSSL_NO_SECURE_MEMORY -idirafter /usr/include/ -idirafter /usr/include/$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
#     MUSL_CFLAGS="-D_FILE_OFFSET_BITS=64"
#     ;;
#   *)
#     WIN_TGT=linux-$(uname -m)
#     ;;
# esac
cat <<'EOF' >&2
KTLS=1 ./build_deps.sh [output libdir]
MYCROSS=aarch64-linux-gnu ./build_deps.sh [output libdir]
        i686-w64-mingw32
        x86_64-w64-mingw32
        musl
if use zlib-ng, ZLIB_NG=1
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
LOGFILE=${LOGFILE:-}
exec > >(tee ${LOGFILE:+-i ${LOGFILE}})
################################################################################
[ -d "${MYLIB_DEPS}" ] && { log "${MYLIB_DEPS} exists!"; exit 1; }
read -n 1 -p "Press any key continue build ..." value
################################################################################
# $(DIRNAME)/lib/libssl.a: $(ODIR)/$(OPENSSL)
# 	@echo Building OpenSSL...
# 	@$(SHELL) -c "cd $< && ./config $(OPENSSL_OPTS)"
# 	@$(MAKE) -C $< depend
# 	@$(MAKE) -C $<
# 	@$(MAKE) -C $< install_sw
# 	@touch $@
# https://www.openssl.org/source/
SRC_DIR=openssl
log "Building ${CC:-} ${SRC_DIR} ...${KTLS:+enable-ktls}.................................."
# Add -D_WIN32_WINNT=0x0501 Configure for Windows XP compatibility
#no-zstd no-zlib \
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./Configure ${MYCROSS:+${WIN_TGT} --cross-compile-prefix=${MYCROSS}-} \
    LIBDIR=lib --prefix=${MYLIB_DEPS} ${KTLS:+enable-ktls} ${MYSSL_INC:-} \
    no-shared no-threads no-dso no-comp no-tests no-legacy no-apps no-docs \
    && perl configdata.pm --dump \
    && make LIBDIR=lib -j "$(nproc)" build_libs \
    && make LIBDIR=lib -j "$(nproc)" install_sw) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

SRC_DIR=expat
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS}} \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --enable-pic=yes \
    --without-xmlwf --without-examples --without-tests \
    --without-docbook && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

SRC_DIR=libiconv
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS}} \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --enable-pic=yes \
    --disable-largefile --disable-rpath \
    --disable-nls && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

# git clone https://github.com/FastCGI-Archives/fcgi2.git
SRC_DIR=fcgi2
# mingw: -Wno-incompatible-pointer-types
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && ./autogen.sh && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    --prefix=${MYLIB_DEPS} \
    CFLAGS="-Wunused-const-variable -Wno-sign-compare -Wno-incompatible-pointer-types" \
    --with-pic --enable-static=yes --enable-shared=no \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

#https://zlib.net/zlib-1.2.11.tar.gz  https://github.com/zlib-ng/zlib-ng
SRC_DIR=zlib
ZLIB_NG=${ZLIB_NG:-} #zlib-ng
log "Building ${CC:-} ${SRC_DIR} ....................................."
ORG_CC=${CC:-}
[ -z "${MYCROSS}" ] && { log "OK build ${SRC_DIR}"; } || {
    export CC=${MYCROSS}-gcc
}
export CFLAGS="-fPIC"
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure --prefix=${MYLIB_DEPS} --static $([ -z "${ZLIB_NG}" ] || echo "--zlib-compat") \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }
unset -v CC CFLAGS
[ -z "${ORG_CC}" ] || export CC=${ORG_CC}

# https://github.com/PCRE2Project/pcre2
SRC_DIR=pcre
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    --prefix=${MYLIB_DEPS} --enable-jit --enable-static=yes --enable-shared=no \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

#https://github.com/akheron/jansson
SRC_DIR=jansson
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS=-fPIC \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

#https://github.com/benmcollins/libjwt ,v1.18.3
SRC_DIR=libjwt
log "Building ${CC:-} ${SRC_DIR} ....................................."
#JANSSON_CFLAGS=-I${MYLIB_DEPS}/include
#JANSSON_LIBS=-L${MYLIB_DEPS}/lib
#OPENSSL_CFLAGS=-I${MYLIB_DEPS}/include
#OPENSSL_LIBS=-L${MYLIB_DEPS}/lib
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    PKG_CONFIG_PATH=${MYLIB_DEPS}/lib/pkgconfig/ ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS=-fPIC \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    --without-examples --disable-doxygen-doc --disable-doxygen-dot --disable-doxygen-man \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }


# https://github.com/TimothyGu/libgnurx
OPENLDAP_CPPFLAGS=""
OPENLDAP_LIBS=""
[ -z "${MYCROSS}" ] || {
    SRC_DIR=mingw-libgnurx
# openldap/include/ac/time.h
# #define timespec linux_timespec
# #include <linux/time.h>
# #undef timespec
    case "${MYCROSS}" in
        *mingw32*)
            OPENLDAP_CPPFLAGS="-DHAVE_CLOCK_GETTIME"
            OPENLDAP_LIBS=-lcrypt32
            log "Building ${CC:-} ${SRC_DIR} ....................................."
            ([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
                ./configure --host=${MYCROSS} \
                LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS="-fPIC" \
                --prefix=${MYLIB_DEPS} \
                && make -j "$(nproc)" \
                && make -j "$(nproc)" install-dev) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }
            ;;
        *)  log "no need ${SRC_DIR}(regex posix)";;
    esac
}

SRC_DIR=openldap
log "Building ${CC:-} ${SRC_DIR} ....................................."
# mingw openldap need gnu regex lib: https://github.com/TimothyGu/libgnurx
# sed -i 's/#define NEED_MEMCMP_REPLACEMENT 1//* #undef NEED_MEMCMP_REPLACEMENT *//' include/portable.h
# or ac_cv_func_memcmp_working=yes
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ac_cv_func_memcmp_working=yes CC=${MYCROSS:+${MYCROSS}-}gcc \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine) --target=${MYCROSS}} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CPPFLAGS="${OPENLDAP_CPPFLAGS} -I${MYLIB_DEPS}/include" CFLAGS="-fPIC" LIBS="${OPENLDAP_LIBS}" \
    --prefix=${MYLIB_DEPS} \
    --disable-debug --disable-dynamic --disable-syslog --disable-slapd --disable-backends --disable-overlays \
    --with-tls=openssl --with-yielding_select=yes \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    && make  CC=${MYCROSS:+${MYCROSS}-}gcc  depend \
    && make  CC=${MYCROSS:+${MYCROSS}-}gcc -C include -j "$(nproc)" \
    && make  CC=${MYCROSS:+${MYCROSS}-}gcc -C libraries -j "$(nproc)" \
    && make -C include -j "$(nproc)" install && make -C libraries -j "$(nproc)" install) \
    && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

SRC_DIR=curl
log "Building ${CC:-} ${SRC_DIR} ....................................."
[ -z "${MYCROSS}" ] || {
    case "${MYCROSS}" in
        *x86_64-*mingw32*) MYCURL_LIB="-lws2_32 -lgdi32 -lcrypt32";;
        *i686-*mingw32*)  MYCURL_LIB="-lws2_32 -lgdi32 -lcrypt32";;
    esac
}
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCURL_LIB:+LIBS="${MYCURL_LIB}"} CPPFLAGS="-DCURL_STATICLIB" ${MYCROSS:+--host=${MYCROSS}} \
    --with-pic=yes --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes \
    --with-openssl=${MYLIB_DEPS} \
    --without-libidn2 \
    --without-libpsl --without-zlib --without-brotli --without-zstd  \
    --without-ldap --disable-ldap --disable-ldaps \
    --disable-alt-svc \
    --disable-docs \
    --disable-ipfs \
    --disable-rtsp && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

# https://download.gnome.org/sources/libxml2/
SRC_DIR=libxml2
log "Building ${CC:-} ${SRC_DIR} ....................................."
[ -z "${MYCROSS}" ] || {
    case "${MYCROSS}" in
        *mingw32*) MY_ICONV_INC="-I${MYLIB_DEPS}/include"
                   MY_ICONV_LIB="-L${MYLIB_DEPS}/lib"
                   ;;
    esac
}
# -lc force use inner iconv, not libiconv
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    CFLAGS="${MY_ICONV_INC:-} -DLIBEXSLT_STATIC -DLIBXSLT_STATIC -DLIBXML_STATIC -fPIC ${MUSL_CFLAGS:-}" ${MY_ICONV_LIB:+LDFLAGS=${MY_ICONV_LIB}} \
    --prefix=${MYLIB_DEPS} \
    --without-debug --without-python \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

# https://download.gnome.org/sources/libxslt/
SRC_DIR=libxslt
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS="-DLIBEXSLT_STATIC -DLIBXSLT_STATIC -DLIBXML_STATIC -fPIC ${MUSL_CFLAGS:-}" \
    --prefix=${MYLIB_DEPS} \
    --with-libxml-include-prefix=${MYLIB_DEPS}/include/libxml2 \
    --with-libxml-libs-prefix=${MYLIB_DEPS}/lib \
    --without-python --without-debug --without-debugger --without-profiler \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    && make -j "$(nproc)" -C libxslt && make -j "$(nproc)" -C libexslt \
    && make -j "$(nproc)" -C libxslt install && make -j "$(nproc)" -C libexslt install \
    && make -j "$(nproc)" install-pkgconfigDATA) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

# https://github.com/maxmind/geoip-api-c
SRC_DIR=geoip
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./bootstrap && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS="-I${MYLIB_DEPS}/include -fPIC" \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    && make -j "$(nproc)" -C libGeoIP \
    && make -j "$(nproc)" -C libGeoIP install \
    && make -j "$(nproc)" install-nodist_pkgconfigDATA) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

SRC_DIR=brotli
# https://github.com/google/brotli.git || ngx_brotli/deps/brotli
log "Building ${CC:-} ${SRC_DIR} ....................................."
[ -z "${MYCROSS}" ] || {
    case "${MYCROSS}" in
        *aarch64-*linux-*)  _BROTLI_SYS=Linux;   _BROTLI_ARCH=arm64;;
        *x86_64-*mingw32*)  _BROTLI_SYS=Windows; _BROTLI_ARCH=amd64;;
        *i686-*mingw32*)    _BROTLI_SYS=Windows; _BROTLI_ARCH=x86;;
        *)                  echo "---${MYCROSS}---TODO::--${SRC_DIR}---"; exit 1;;
    esac
}
([ -d "${SRC_DIR}" ] && { log "clean ${SRC_DIR}...."; rm -fr ${SRC_DIR}-build &>/dev/null||true; } && \
    mkdir -p ${SRC_DIR}-build \
    && cmake ${CC:+-DCMAKE_C_COMPILER=${CC}} ${MYCROSS:+-DCMAKE_SYSTEM_NAME=${_BROTLI_SYS} -DCMAKE_SYSTEM_PROCESSOR=${_BROTLI_ARCH} -DCMAKE_C_COMPILER=${MYCROSS}-gcc -DCMAKE_C_COMPILER_TARGET=${MYCROSS}} \
        -S ${SRC_DIR} -B ${SRC_DIR}-build \
        --install-prefix ${MYLIB_DEPS} \
        -DBUILD_SHARED_LIBS=OFF \
    && cmake --build ${SRC_DIR}-build --target install --config Release)  && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

# https://bellard.org/quickjs/
SRC_DIR=quickjs
[ -z "${MYCROSS}" ] || {
    case "${MYCROSS}" in
        *aarch64-*linux-*)  export CROSS_PREFIX=${MYCROSS}-;;
        *x86_64-*mingw32*)  export CONFIG_WIN32=1;;
        *i686-*mingw32*)    export CONFIG_WIN32=1; export CONFIG_M32=1;;
        *)                  echo "---${MYCROSS}---TODO::--${SRC_DIR}---"; exit 1;;
    esac
}
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make clean &>/dev/null||true; } \
    && CFLAGS='-fPIC' make ${CC:+CC=${CC}} -j "$(nproc)" libquickjs.a \
    && mkdir -p "${MYLIB_DEPS}/include/quickjs" "${MYLIB_DEPS}/lib/quickjs" \
    && install -v -m644 libquickjs.a "${MYLIB_DEPS}/lib/quickjs" \
	&& install -v -m644 quickjs.h quickjs-libc.h "${MYLIB_DEPS}/include/quickjs") && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }
    # && make -j "$(nproc)" PREFIX=${MYLIB_DEPS} install
unset -v CROSS_PREFIX CONFIG_WIN32 CONFIG_M32

SRC_DIR=sqlite
log "Building ${CC:-} ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    CFLAGS=-fPIC \
    --prefix=${MYLIB_DEPS} \
    --disable-shared && make -j "$(nproc)" libsqlite3.a sqlite3.pc \
    && make -j "$(nproc)" install-headers install-pc install-lib) && { log "OK build ${SRC_DIR}"; } || { log "error build ${SRC_DIR}"; }

log "Building ${CC:-} COMPLETE"
