#include <stdio.h>
#include "demo.h"

int dllmain(int argc, char *argv[]) {
    for (int i = 0; i < argc; ++i) {
        debugln("input %d, %s\n", i, argv[i]);
    }
    return 0;
}
void Initializer() {
    printf("Library initialized!\n");
}
void Deinitializer() {
    printf("Library deinitialized!\n");
}
#if defined __WIN32__
BOOL APIENTRY DllMain(HMODULE hModule, DWORD  ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH: Initializer(); break
        case DLL_THREAD_ATTACH:
        case DLL_THREAD_DETACH:
        case DLL_PROCESS_DETACH: Deinitializer(); break;
    }
    return TRUE;
}
#endif
