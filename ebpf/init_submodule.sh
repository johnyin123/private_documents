#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

# git submodule add https://github.com/libbpf/libbpf.git libbpf
# git add libbpf/
# git commit
# git push

# git submodule update --init

# apt -y install llvm && cd ${kernel}/tools/bpf/bpftool && make
make -C ${DIRNAME}/libbpf/src \
         BUILD_STATIC_ONLY=1 \
         OBJDIR=${DIRNAME} DESTDIR= \
         INCLUDEDIR=${DIRNAME}/inc LIBDIR=${DIRNAME}/lib UAPIDIR= \
         install
