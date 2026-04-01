/* gcc -x c test.cc -L./ -lneusoft -Wl,-rpath,./ -o test.dll */
#include "demo.h"
int main(int argc, char *argv[]) {
    return dllmain(argc, argv);
}
