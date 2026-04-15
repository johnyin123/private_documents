EXE     ?=libHeaSecReadInfo.so
CFLAGS  +=-DCJSON_HIDE_SYMBOLS -DCURL_STATICLIB -DBUILDING_LIBRARY
CFLAGS  +=-D_GNU_SOURCE -D_XOPEN_SOURCE=700 -fvisibility=hidden -flto -march=native -funroll-loops
LDFLAGS +=-shared
LDFLAGS +=-L./ -lSSCardDriver -Wl,--no-as-needed -L./ -ldcrf32
# static link libs
LDFLAGS +=-Wl,-Bstatic -lcurl -lssl -lcrypto -lexpat -liconv
# not export static link libs funcs
LDFLAGS +=-Wl,--exclude-libs,ALL
# othre dynamic link
LDFLAGS +=-Wl,-Bdynamic
LIBFLAGS+=-Wl,-rpath,./
LDFLAGS +=-static-libgcc
INC_PATH+=-I./mylibs.linux-x86_64/include
LIB_PATH+=-L./mylibs.linux-x86_64/lib

test: $(EXE)
	@printf "\033[1;32m  build test \033[m\n"
	@LD_LIBRARY_PATH=./mylibs.linux-x86_64/lib $(CC) -x c test.cc -L./ -lHeaSecReadInfo -Wl,-rpath,./ -o libtest
