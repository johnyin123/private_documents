/*
gcc test.cc -L./ -lneusoft -Wl,-rpath,./ # -l:test.so
*/
#include "demo.h"
int main(int argc, char *argv[])
{
    return dllmain(argc, argv);
}
