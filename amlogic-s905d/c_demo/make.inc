CROSS_COMPILE=
EXE     ?=libHeaSecReadInfo.x86_64.so
CFLAGS  +=-DCJSON_HIDE_SYMBOLS -DCURL_STATICLIB -DBUILDING_LIBRARY
CFLAGS  +=-D_GNU_SOURCE -D_XOPEN_SOURCE=700 -fvisibility=hidden -flto -march=native -funroll-loops
LDFLAGS +=-shared
LDFLAGS +=-L./ -lSSCardDriver
LDFLAGS +=-Wl,--no-as-needed -L./ -ldcrf32
# static link libs
LDFLAGS +=-Wl,-Bstatic -lcurl -lssl -lcrypto -lexpat -liconv
# not export static link libs funcs
LDFLAGS +=-Wl,--exclude-libs,ALL
# othre dynamic link
LDFLAGS +=-Wl,-Bdynamic
LIBFLAGS+=-Wl,-rpath,./
LDFLAGS +=-static-libgcc -static-libstdc++
INC_PATH+=-I./mylibs.linux-x86_64/include
LIB_PATH+=-L./mylibs.linux-x86_64/lib

test: $(EXE)
	@printf "\033[1;32m BUILD TEST \033[m\n"
	@$(CC) -x c test.cc -L./ -lHeaSecReadInfo.x86_64 -Wl,-rpath-link=./mylibs.linux-x86_64/lib -Wl,-rpath,./ -o libtest.x86_64
