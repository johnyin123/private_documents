#include <stdio.h>
#include "demo.h"
struct env {
    int trace_level;
} env = {
    .trace_level = 0,
};
#include <stdio.h>
#define debugln(fmt,args...) { if(env.trace_level>5) fprintf(stderr, "DBG: "fmt"\n", ##args); }
LIB_INIT void Initializer() {
    const char* env_val = getenv("TRACE");
    if(env_val) env.trace_level = atoi(env_val);
    debugln("Library initialized!\n");
}
LIB_DEINIT void Deinitializer() {
    debugln("Library deinitialized!\n");
}
#if defined __WIN32__
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH: Initializer(); break;
        case DLL_THREAD_ATTACH:
        case DLL_THREAD_DETACH:
        case DLL_PROCESS_DETACH: Deinitializer(); break;
    }
    return TRUE;
}
#endif
EXPORT_API int dllmain(int argc, char *argv[]) {
    for (int i = 0; i < argc; ++i) {
        debugln("input %d, %s\n", i, argv[i]);
    }
    return 0;
}
