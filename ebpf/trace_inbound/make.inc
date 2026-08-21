EXE=loader
CFLAGS+=-D_GNU_SOURCE -D__USE_XOPEN
LDFLAGS+=-Wl,-Bstatic -lbpf
LDFLAGS+=-Wl,-Bdynamic -lelf -lz -lzstd -pthread
# LDFLAGS+=-Wl,--start-group -lelf -leu -Wl,--end-group
LDFLAGS+=-static-libgcc -static-libstdc++
# LDFLAGS+=-static
LIBFLAGS+= # -Wl,-rpath,./  # relative path .so load
INC_PATH+=-I./inc
LIB_PATH+=-L./lib

# apt install -y gcc-bpf binutils-bpf
# bpf-gcc -g -O2 -I/usr/include -I/usr/include/$(uname -m)-linux-gnu -I./inc -c redirect.bpf.c
# ip link set dev $1 xdp obj ${SCRIPTPATH}/../ebpf/xdp_redirect.o sec xdp
# cat /sys/kernel/debug/tracing/trace_pipe
# ip link set ens193f0 xdp object ./router.bpf.o
# ip link show dev eth0
# ip link set dev eth0 xdp off
