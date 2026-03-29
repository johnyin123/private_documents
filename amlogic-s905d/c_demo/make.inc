EXE?=libneusoft.so
CFLAGS+=-DBUILDING_LIBRARY -DCURL_STATICLIB -D_GNU_SOURCE -D__USE_XOPEN -O2 -fvisibility=hidden -march=native -mfpmath=sse -Ofast -flto -march=native -funroll-loops
LDFLAGS+=-shared
LDFLAGS+=-Wl,-Bstatic -lcurl -Wl,-Bdynamic
LIBFLAGS+=-Wl,-rpath,./
INC_PATH+=-I./curl/include
LIB_PATH+=-L./curl/lib/.libs

# EXE?=test
# LDFLAGS+=-lneusoft
# LIBFLAGS+=-Wl,-rpath,./  # relative path
# LIB_PATH+=-L./
