INCFILE=make.inc
ifeq ($(INCFILE), $(wildcard $(INCFILE)))
include $(INCFILE)
# make.inc -->
# EXE=my_uprobe
# CFLAGS=-D_GNU_SOURCE -D__USE_XOPEN -I../dep/include
# LDFLAGS=-L./ -lbpf -lelf -lz
endif
VMLINUX     := vmlinux.h
# LIBBPF_OBJ  := libbpf.a
ARCH        ?= $(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/' | sed 's/ppc64le/powerpc/' | sed 's/mips.*/mips/')
EXE         ?= main_bpf
CFLAGS      += -g -Wall
CLANG       := clang -g -O2 -Wall -D__TARGET_ARCH_$(ARCH)
LLVM_STRIP  := llvm-strip
RM          := rm -f
BPFTOOL     := /usr/sbin/bpftool


BPF_SRC=$(wildcard *.bpf.c)
USR_SRC=$(filter-out $(wildcard *.bpf.c), $(wildcard *.c))
USR_OBJ=$(USR_SRC:.c=.o)
BPF_OBJ=$(BPF_SRC:.c=.o)
BPF_SKEL=$(BPF_SRC:.bpf.c=_skel.h)

# Get Clang's default includes on this system. We'll explicitly add these dirs
# to the includes list when compiling with `-target bpf` because otherwise some
# architecture-specific dirs will be "missing" on some architectures/distros -
# headers such as asm/types.h, asm/byteorder.h, asm/socket.h, asm/sockios.h,
# sys/cdefs.h etc. might be missing.
#
# Use '-idirafter': Don't interfere with include mechanics except where the
# build would have failed anyways.
CLANG_BPF_SYS_INCLUDES = $(shell $(CLANG) -v -E - </dev/null 2>&1 \
    | sed -n '/<...> search starts here:/,/End of search list./{ s| \(/.*\)|-idirafter \1|p }')

ifeq ($(DEBUG),1)
CFLAGS += -DDEBUG
endif
ifeq ($(V),1)
Q =
msg =
else
Q = @
msg = @printf '  %-8s %s%s\n' "$(1)" "$(notdir $(2))" "$(if $(3), $(3))";
endif

.PHONY : all
all: $(EXE)
$(EXE): $(USR_OBJ)
	$(call msg,BINARY,$@)
	$(Q)$(CC) $(CFLAGS) $^ $(LDFLAGS) -o $@

.PHONY : clean
clean:
	$(call msg,CLEAN)
	$(Q)$(RM) $(USR_OBJ) $(BPF_OBJ) $(BPF_SKEL) $(VMLINUX) $(EXE)

$(filter %.o,$(BPF_OBJ)): %.o: %.c $(VMLINUX)
	$(call msg,BPF_BIN,$@)
	$(Q)$(CLANG) -target bpf $(CLANG_BPF_SYS_INCLUDES) -o $@ -c $<
	$(call msg,BPF_BIN,strip $@ useless DWARF info)
	$(Q)$(LLVM_STRIP) -g $@
	$(call msg,BPF_SKEL,$(subst .bpf,_skel,$*).h name:$(subst .bpf,_skel,$*))
	$(Q)$(BPFTOOL) gen skeleton $@ name $(subst .bpf,_skel,$*) > $(subst .bpf,_skel,$*).h

$(filter %.o,$(USR_OBJ)): %.o: %.c $(BPF_OBJ)
	$(call msg,USR_OBJ,$@)
	$(Q)$(CC) $(CFLAGS) -o $@ -c $<

$(VMLINUX):
	$(call msg,BPF,$@)
	$(Q)$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

help:
	@echo "clean/help/all"
	@echo "export DEBUG=1;make V=1"
	@echo "make DEBUG=1 V=1"
