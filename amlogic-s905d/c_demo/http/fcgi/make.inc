CROSS_COMPILE=
EXE     ?=mycgi
CFLAGS  +=-Wno-unused-parameter
CFLAGS  +=-D_GNU_SOURCE -D_XOPEN_SOURCE=700 -fvisibility=hidden -flto -march=native -funroll-loops
LDFLAGS +=-lfcgi
INC_PATH+=-I./mylibs.linux-x86_64/include
LIB_PATH+=-L./mylibs.linux-x86_64/lib
