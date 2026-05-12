#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
MYCROSS=${MYCROSS:-}  # x86_64-w64-mingw32 / i686-w64-mingw32 / aarch64-linux-gnu
WIN_TGT=linux-x86_64
[ "${MYCROSS:-}" == "i686-w64-mingw32" ] && { WIN_TGT=mingw; MYCURL_LIB="-lws2_32 -lgdi32 -lcrypt32"; }
[ "${MYCROSS:-}" == "x86_64-w64-mingw32" ] && { WIN_TGT=mingw64; MYCURL_LIB="-lws2_32 -lgdi32 -lcrypt32"; }
[ "${MYCROSS:-}" == "aarch64-linux-gnu" ] && WIN_TGT=linux-aarch64
cat <<'EOF'
KTLS=1 ./build_deps.sh [output libdir]
MYCROSS=aarch64-linux-gnu ./build_deps.sh [output libdir]

$(DIRNAME)/lib/libssl.a: $(ODIR)/$(OPENSSL)
	@echo Building OpenSSL...
	@$(SHELL) -c "cd $< && ./config $(OPENSSL_OPTS)"
	@$(MAKE) -C $< depend
	@$(MAKE) -C $<
	@$(MAKE) -C $< install_sw
	@touch $@
EOF
MYLIB_DEPS=${1:-${DIRNAME}/mylibs.${WIN_TGT}}
[ -d "${MYLIB_DEPS}" ] && MYLIB_DEPS="$(readlink -f "${MYLIB_DEPS}")"
################################################################################
RED='\033[31m'
GREEN='\033[32m'
NC='\033[0m'
log() { printf "[${GREEN}$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')${NC}]${RED}%b${NC}\n" "$@"; }
[ -d "${MYLIB_DEPS}" ] && { log "${MYLIB_DEPS} exists!"; exit 1; }
################################################################################
SRC_DIR=openssl
log "Building ${SRC_DIR} ...${KTLS:+enable-ktls}.................................."
#no-zstd no-zlib \
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./Configure ${MYCROSS:+${WIN_TGT} --cross-compile-prefix=${MYCROSS}-} \
    LIBDIR=lib --prefix=${MYLIB_DEPS} ${KTLS:+enable-ktls} \
    no-shared no-threads no-tests no-legacy no-apps no-docs \
    && perl configdata.pm --dump \
    && make LIBDIR=lib -j "$(nproc)" build_libs \
    && make LIBDIR=lib -j "$(nproc)" install_sw) || { log 'error build openssl'; }

SRC_DIR=curl
log "Building ${SRC_DIR} ....................................."
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
    && make -j "$(nproc)" install) || { log 'error build libcurl'; }

SRC_DIR=expat
log "Building ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS}} \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --enable-pic=yes \
    --without-xmlwf --without-examples --without-tests \
    --without-docbook && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { log 'error build expat'; }

SRC_DIR=libiconv
log "Building ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS}} \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --enable-pic=yes \
    --disable-largefile --disable-rpath \
    --disable-nls && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { log 'error build iconv'; }

SRC_DIR=fcgi2
log "Building ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && ./autogen.sh && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    --prefix=${MYLIB_DEPS} \
    CFLAGS=-Wunused-const-variable \
    --with-pic --enable-static=yes --enable-shared=no \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { log 'error build fcgi2'; }

SRC_DIR=zlib
log "Building ${SRC_DIR} ....................................."
[ -z "${MYCROSS}" ] || {
   export CC=${MYCROSS}-gcc
}
export CFLAGS="-fPIC"
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure --prefix=${MYLIB_DEPS} --static \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { log 'error build zlib'; }
unset -v CC CFLAGS

SRC_DIR=pcre
log "Building ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    --prefix=${MYLIB_DEPS} --enable-jit --enable-static=yes --enable-shared=no \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { log 'error build pcre2'; }

SRC_DIR=jansson
log "Building ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS=-fPIC \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { log 'error build jansson'; }

SRC_DIR=libjwt
log "Building ${SRC_DIR} ....................................."
# deps openssl(special verson), jansson
#JANSSON_CFLAGS=-I${MYLIB_DEPS}/include
#JANSSON_LIBS=-L${MYLIB_DEPS}/lib
#OPENSSL_CFLAGS=-I${MYLIB_DEPS}/include
#OPENSSL_LIBS=-L${MYLIB_DEPS}/lib
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS=-fPIC \
    --prefix=${MYLIB_DEPS} \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    --without-openssl --without-examples --disable-doxygen-doc --disable-doxygen-dot --disable-doxygen-man \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install) || { log 'error build libjwt'; }

SRC_DIR=openldap
log "Building ${SRC_DIR} ....................................."
([ -d "${SRC_DIR}" ] && cd "${SRC_DIR}" && { log "clean ${SRC_DIR}...."; make distclean &>/dev/null||true; } && \
    ac_cv_func_memcmp_working=yes \
    ./configure ${MYCROSS:+--host=${MYCROSS} --build=$(gcc -dumpmachine)} \
    LDFLAGS=-L${MYLIB_DEPS}/lib CFLAGS=-fPIC \
    --prefix=${MYLIB_DEPS} \
    --disable-debug --disable-dynamic --disable-syslog --disable-slapd --disable-backends --disable-overlays \
    --with-tls=openssl --with-yielding_select=yes \
    --enable-shared=no --enable-static=yes --with-pic=PIC \
    && make -j "$(nproc)" \
    && make -j "$(nproc)" -C libraries install) || { log 'error build openldap'; }

log "Building COMPLETE"
