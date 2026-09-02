INCFILE     ?= make.inc
-include $(INCFILE)
# make.inc -->
# EXE=my_uprobe
# CFLAGS=-D_GNU_SOURCE -D__USE_XOPEN
# LDFLAGS=-lbpf -lelf -lz
# LIBFLAGS+=-Wl,-rpath,./  # relative path .so load
# INC_PATH+=#-I../deps/LuaJIT-2.0.4/src -I../deps/hiredis
# LIB_PATH+=#-L../deps/LuaJIT-2.0.4/src -L../deps/hiredis
VMLINUX     := vmlinux.h
DEBUG_FLAG  += -Wall -Wextra
C_STANDARD   = -std=c99
EXE         ?= main_bpf
CFLAGS      += -g -Wall
BPF_CC      := bpf-gcc -g -gbtf -O2 -Wall -I/usr/include -I/usr/include/$(shell uname -m)-linux-gnu
BPF_STRIP   := bpf-strip
RM          := rm -f
BPFTOOL     := /usr/sbin/bpftool

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
BPF_SKEL=$(BPF_SRC:.bpf.c=_skel.h)

ifdef DEBUG
	DEBUG_FLAG+=-O0 -g -DDEBUG -fvisibility=hidden
else
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
	$(Q)$(RM) $(USR_OBJ) $(BPF_OBJ) $(BPF_SKEL) $(VMLINUX) $(EXE)

$(filter %.o,$(BPF_OBJ)): %.o: %.c $(VMLINUX)
	$(call msg,BPF_BIN,$@)
	$(Q)$(BPF_CC) $(CFLAGS) $(INC_PATH) -o $@ $(ARCH_FLAG) -c $<
	$(call msg,BPF_BIN,strip $@ useless DWARF info)
	$(Q)$(BPF_STRIP) -g $@
	$(call msg,BPF_SKEL,$(subst .bpf,_skel,$*).h name:$(subst .bpf,,$*))
	$(Q)$(BPFTOOL) gen skeleton $@ name $(subst .bpf,,$*) > $(subst .bpf,_skel,$*).h

$(filter %.o,$(USR_OBJ)): %.o: %.c $(BPF_OBJ)
	$(call msg,USR_OBJ,$@)
	$(Q)$(CC) $(C_STANDARD) $(CFLAGS) $(DEBUG_FLAG) $(INC_PATH) -o $@ -c $<

$(VMLINUX):
	$(call msg,BPF,$@)
	$(Q)$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

help:
	@echo "clean/help/all"
	@echo "export DEBUG=1;make V=1"
	@echo "make DEBUG=1 V=1"
