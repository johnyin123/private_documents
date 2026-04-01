EXE     ?=libHeaSecReadInfo.so
CFLAGS  +=-DCURL_STATICLIB -DBUILDING_LIBRARY -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -fvisibility=hidden -flto -march=native -funroll-loops
LDFLAGS +=-shared
LDFLAGS +=-L./ -lSSCardDriver -Wl,--no-as-needed -L./ -ldcrf32
LDFLAGS +=-Wl,-Bstatic -lcurl -lssl -lcrypto -lexpat -liconv -Wl,-Bdynamic
LIBFLAGS+=-Wl,-rpath,./
INC_PATH+=-I./mylibs.linux-x86_64/include
LIB_PATH+=-L./mylibs.linux-x86_64/lib
