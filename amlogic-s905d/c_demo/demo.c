#include <stdio.h>
#include <stdlib.h>
#include "demo.h"
struct env {
    int trace_level;
    FILE *logfile;
} g_env = {
    .trace_level = 0,
};
#define debugln(fmt,args...) { if(g_env.trace_level>5 && g_env.logfile) fprintf(g_env.logfile, "DBG: "fmt"\n", ##args); }
LIB_INIT void Initializer() {
    const char* env_val = getenv("TRACE");
    if(env_val) g_env.trace_level = atoi(env_val);
    g_env.logfile = stderr;
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
