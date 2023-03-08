INCFILE=make.inc
ifeq ($(INCFILE), $(wildcard $(INCFILE)))
include $(INCFILE)
# make.inc -->
# EXE=ffff
# CFLAGS+=-D_GNU_SOURCE -D__USE_XOPEN -O2 -march=native -mfpmath=sse  -Ofast -flto -march=native -funroll-loops
# LIBFLAGS+=-lluajit -lhiredis -lsqlite3 -lm -ldl -lpthread#`pkg-config --libs libssl` 
# LDFLAGS+=#-static#-Wl,-Bstatic -libc -Wl,-Bdynamic
# INC_PATH+=#-I../deps/LuaJIT-2.0.4/src -I../deps/hiredis
# LIB_PATH+=#-L../deps/LuaJIT-2.0.4/src -L../deps/hiredis
endif
ARCH        ?= $(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/' | sed 's/ppc64le/powerpc/' | sed 's/mips.*/mips/')
CLANG_FLAGS ?=-I/usr/include/linux/ -I/usr/src/linux-headers-6.1.12-johnyin/include/ -I/usr/include/x86_64-linux-gnu/
EXE         ?= main_bpf
CC          := gcc -g -O2 -Wall
CLANG       := clang -g -O2 -Wall -D__TARGET_ARCH_$(ARCH) $(CLANG_FLAGS)
RM          := rm -f
BPFTOOL     := /usr/sbin/bpftool


BPF_SRC=$(wildcard *.bpf.c)
USR_SRC=$(filter-out $(wildcard *.bpf.c), $(wildcard *.c))
USR_OBJ=$(USR_SRC:.c=.o)
BPF_OBJ=$(BPF_SRC:.c=.o)
BPF_SKEL=$(BPF_SRC:.bpf.c=_skel.h)

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
	$(Q)$(CC) $(USR_OBJ) -static -lbpf -lelf -lz $(LIB_PATH) $(LDFLAGS) -o $@ $(LIBFLAGS)

.PHONY : clean
clean:
	$(call msg,CLEAN)
	$(Q)$(RM) $(USR_OBJ) $(BPF_OBJ) $(BPF_SKEL) vmlinux.h $(EXE)

$(filter %.o,$(BPF_OBJ)): %.o: %.c vmlinux.h
	$(call msg,BPF_BIN,$@)
	$(Q)$(CLANG) -target bpf $(CFLAGS) $(INC_PATH) -o $@ -c $<
	$(Q)$(BPFTOOL) gen skeleton $@ name $(subst .bpf,_skel,$*) > $(subst .bpf,_skel,$*).h

$(filter %.o,$(USR_OBJ)): %.o: %.c $(BPF_OBJ)
	$(call msg,USR_OBJ,$@)
	$(Q)$(CC) $(CFLAGS) $(INC_PATH) -o $@ -c $<

vmlinux.h:
	$(call msg,BPF,$@)
	$(Q)$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

help:
	@echo "clean/help/all"
	@echo "export DEBUG=1;make V=1"
	@echo "make DEBUG=1 V=1"
