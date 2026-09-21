INCFILE     ?= make.inc
-include $(INCFILE)
# make.inc -->
# EXE=my_uprobe
# CFLAGS=-D_GNU_SOURCE -D__USE_XOPEN
# LDFLAGS=-lbpf -lelf -lz
# LIBFLAGS+=-Wl,-rpath,./  # relative path .so load
# INC_PATH+=#-I../deps/LuaJIT-2.0.4/src -I../deps/hiredis
# LIB_PATH+=#-L../deps/LuaJIT-2.0.4/src -L../deps/hiredis
# BPF_SKEL=bpf_skel.h
VMLINUX     := vmlinux.h
DEBUG_FLAG  += -Wall -Wextra
C_STANDARD   = -std=c99
EXE         ?= main_bpf
CFLAGS      += -g -Wall
BPF_CC      := bpf-gcc -g -O2 -Wall -gbtf $(shell gcc -v -E - </dev/null 2>&1 | sed -n '/<...> search starts here:/,/End of search list./{ s| \(/.*\)|-idirafter \1|p }')
BPF_STRIP   := bpf-strip
# BPF_CC      := clang -g -O2 -Wall -target bpf $(shell clang -v -E - </dev/null 2>&1 | sed -n '/<...> search starts here:/,/End of search list./{ s| \(/.*\)|-idirafter \1|p }')
# BPF_STRIP   := llvm-strip
RM          := rm -f
BPFTOOL     := /usr/sbin/bpftool

ifneq (,$(wildcard ./config.h))
	CFLAGS += -DHAVE_CONFIG_H
endif
HOST_ARCH ?= $(shell uname -m)
ifeq ($(HOST_ARCH),x86_64)
	ARCH_FLAG = -D__x86_64__ -D__TARGET_ARCH_x86
else ifeq ($(HOST_ARCH),aarch64)
	ARCH_FLAG = -D__aarch64__ -D__TARGET_ARCH_arm64
endif

BPF_SRC=$(wildcard *.bpf.c)
USR_SRC=$(filter-out $(wildcard *.bpf.c), $(wildcard *.c))
USR_OBJ=$(USR_SRC:.c=.o)
BPF_OBJ=$(BPF_SRC:.c=.o)
BPF_CNT=$(words $(BPF_OBJ))
# If BPF_CNT is 1, BPF_SKEL becomes BPF_OBJ. Otherwise, it defaults to BPF_SKEL
ifeq ($(BPF_CNT),1)
	BPF_SKEL?=$(BPF_OBJ:.bpf.o=_skel.h)
endif

ifdef DEBUG
	BPF_CC_DEBUG_FLAG = -DDEBUG -Wall -Wextra
	DEBUG_FLAG+=-O0 -g -DDEBUG -fvisibility=hidden
else
	BPF_CC_DEBUG_FLAG = -Wall -Wextra
	DEBUG_FLAG+=-O3 -fvisibility=hidden -fomit-frame-pointer -pipe
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
	$(Q)$(CC) $(USR_OBJ) $(DEBUG_FLAG) $(LIB_PATH) -o $@ $(LIBFLAGS) $(LDFLAGS)

.PHONY : clean
clean:
	$(call msg,CLEAN)
	$(Q)$(RM) $(USR_OBJ) $(BPF_OBJ) $(BPF_SKEL) $(BPF_SKEL:.h=.o) $(VMLINUX) $(EXE)

$(filter %.o,$(BPF_OBJ)): %.o: %.c $(VMLINUX)
	$(call msg,BPF_BIN,$@)
	$(Q)$(BPF_CC) $(CFLAGS) $(BPF_CC_DEBUG_FLAG) $(INC_PATH) -o $@ $(ARCH_FLAG) -c $<
	$(call msg,BPF_BIN,strip $@ useless DWARF info)
	$(Q)$(BPF_STRIP) -g $@

$(BPF_SKEL): $(BPF_OBJ)
	$(call msg,BPF_SKEL,$@)
	$(Q)$(BPFTOOL) gen object $(BPF_SKEL:.h=.o) $(BPF_OBJ)
	$(Q)$(BPFTOOL) gen skeleton $(BPF_SKEL:.h=.o) name $(BPF_SKEL:.h=) > $@

$(filter %.o,$(USR_OBJ)): %.o: %.c $(BPF_SKEL)
	$(call msg,USR_OBJ,$@)
	$(Q)$(CC) $(C_STANDARD) $(CFLAGS) $(DEBUG_FLAG) $(INC_PATH) -o $@ -c $<

$(VMLINUX):
	$(call msg,BPF,$@)
	$(Q)$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

help:
	@echo "clean/help/all"
	@echo "export DEBUG=1;make V=1"
	@echo "make DEBUG=1 V=1"
