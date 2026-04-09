#include <stdio.h>
#include <stdlib.h>
#include "demo.h"
struct env {
    int trace_level;
} g_env = {
    .trace_level = 0,
};
#ifdef USE_SYSLOG
#include <syslog.h>
#define debugln(fmt,args...) do { if(g_env.trace_level>LOG_DEBUG) syslog(LOG_DEBUG, "DBG: "fmt"\n", ##args) } while(0)
#else
#define	LOG_EMERG	0	/* system is unusable */
#define	LOG_ALERT	1	/* action must be taken immediately */
#define	LOG_CRIT	2	/* critical conditions */
#define	LOG_ERR		3	/* error conditions */
#define	LOG_WARNING	4	/* warning conditions */
#define	LOG_NOTICE	5	/* normal but significant condition */
#define	LOG_INFO	6	/* informational */
#define	LOG_DEBUG	7	/* debug-level messages */
#define debugln(fmt,args...) do { if(g_env.trace_level>LOG_DEBUG) fprintf(stderr, "DBG: "fmt"\n", ##args); } while(0)
#endif

LIB_INIT void Initializer() {
    const char* env_val = getenv("TRACE");
    if(env_val) g_env.trace_level = atoi(env_val);
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
