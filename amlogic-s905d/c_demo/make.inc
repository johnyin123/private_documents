EXE     ?=libHeaSecReadInfo.so
CFLAGS  +=-DBUILDING_LIBRARY -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -fvisibility=hidden -march=native -flto -march=native -funroll-loops
LDFLAGS +=-shared
LDFLAGS +=-L./ -lSSCardDriver  -Wl,--no-as-needed -L./ -ldcrf32
LDFLAGS +=-Wl,-Bstatic -lcurl -lssl -lcrypto -lexpat -Wl,-Bdynamic
LIBFLAGS+=-Wl,-rpath,./
INC_PATH+=-I./mylibs/include
LIB_PATH+=-L./mylibs/lib
