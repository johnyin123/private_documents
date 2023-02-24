ifndef EXE
	EXE=main_bpf
endif

CC          := clang -g -O2 -Wall
RM          := rm -f

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

USR_SRC=main.c
BPF_SRC=mybpf.c
USR_OBJ=$(USR_SRC:.c=.o)
BPF_OBJ=$(BPF_SRC:.c=.o)
BPF_SKEL=$(BPF_SRC:.c=_skel.h)

.PHONY : all
all: $(EXE)
$(EXE): $(USR_OBJ)
	$(CC) $(USR_OBJ) -static -lbpf -lelf -lz $(LIB_PATH) $(LDFLAGS) -o $@ $(LIBFLAGS)

.PHONY : clean
clean:
	-$(RM) $(USR_OBJ) $(BPF_OBJ) $(BPF_SKEL) vmlinux.h $(EXE)

$(BPF_OBJ): $(BPF_SRC) vmlinux.h
	@echo -n "\033[1;31m BPF ## "
	$(CC) -target bpf $(CFLAGS) $(INC_PATH) -o $@ -c $<
	@echo -n "\033[m"

$(BPF_SKEL): $(BPF_OBJ)
	@echo -n "\033[1;31m BPF SKEL ## "
	bpftool gen skeleton $< name $* > $@
	# bpftool gen skeleton $< > $@
	@echo -n "\033[m"

$(USR_OBJ): $(USR_SRC) $(BPF_SKEL)
	@echo -n "\033[1;31m USR ## "
	$(CC) $(CFLAGS) $(INC_PATH) -o $@ -c $<
	@echo -n "\033[m"

vmlinux.h:
	@echo -n "\033[1;31m GEN vmlinux.h ## "
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@
	@echo -n "\033[m"


