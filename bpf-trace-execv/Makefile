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
EXE         ?= main_bpf
CC          := gcc -g -O2 -Wall
CLANG       := clang -g -O2 -Wall
RM          := rm -f
BPFTOOL     := /usr/sbin/bpftool
USR_SRC=main.c
BPF_SRC=mybpf.c
USR_OBJ=$(USR_SRC:.c=.o)
BPF_OBJ=$(BPF_SRC:.c=.o)
BPF_SKEL=$(BPF_SRC:.c=_skel.h)

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

$(BPF_OBJ): $(BPF_SRC) vmlinux.h
	$(call msg,BPF_BIN,$@)
	$(Q)$(CLANG) -target bpf $(CFLAGS) $(INC_PATH) -o $@ -c $<

$(BPF_SKEL): $(BPF_OBJ)
	$(call msg,BPF_SKEL,$@)
	$(Q)$(BPFTOOL) gen skeleton $< name $* > $@

$(filter %.o,$(USR_OBJ)): %.o: %.c $(BPF_SKEL)
	$(call msg,USR_OBJ,$@)
	$(Q)$(CC) $(CFLAGS) $(INC_PATH) -o $@ -c $<

vmlinux.h:
	$(call msg,BPF,$@)
	$(Q)$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@
