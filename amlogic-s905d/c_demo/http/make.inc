EXE?=http
CFLAGS+=-D_GNU_SOURCE -D__USE_XOPEN -O2 -fvisibility=hidden -march=native -mfpmath=sse -Ofast -flto -march=native -funroll-loops
LDFLAGS+=
LIBFLAGS+=-Wl,-rpath,./
INC_PATH+=
LIB_PATH+=-L./
