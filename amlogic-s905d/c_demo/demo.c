#include <stdio.h>
#include <stdlib.h>
#include "demo.h"
struct env {
    int trace_level;
} g_env = {
    .trace_level = 0,
};
#define ARRAY_LEN(a)          (sizeof(a)/sizeof((a)[0]))
#define UNUSED(x)             ((void)(x))
#ifdef USE_SYSLOG
#include <syslog.h>
#define log_debug(fmt,args...)  { if(g_env.trace_level>=LOG_DEBUG) syslog(LOG_DEBUG, "DEBUG %s:%d " fmt "\n", __FILE__, __LINE_, _##args); }
#define log_info(fmt,args...)   { if(g_env.trace_level>=LOG_INFO)  syslog(LOG_INFO,  fmt "\n", ##args); }
#define log_error(fmt,args...)  { if(g_env.trace_level>=LOG_ERR)   syslog(LOG_ERR,   fmt "\n", ##args); }
#else
enum { LOG_EMERG=0, LOG_ALERT=1, LOG_CRIT=2, LOG_ERR=3, LOG_WARNING=4, LOG_NOTICE=5, LOG_INFO=6, LOG_DEBUG=7 };
#define log_debug(fmt,args...)  { if(g_env.trace_level>=LOG_DEBUG) fprintf(stderr, "DEBUG %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_info(fmt,args...)   { if(g_env.trace_level>=LOG_INFO)  fprintf(stderr, "INFO  %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_error(fmt,args...)  { if(g_env.trace_level>=LOG_ERR)   fprintf(stderr, "ERROR %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#endif
#ifdef DEBUG
#include <time.h>
#define SHOW_EXECUTION_TIME(func_call) ({ \
    clock_t start = clock(); \
    __auto_type _result = (func_call); \
    clock_t end = clock(); \
    if(__builtin_types_compatible_p(__typeof__(_result), int)) log_debug("[%s] return %d", #func_call, _result); \
    double elapsed = (double)(end - start) / CLOCKS_PER_SEC; \
    log_debug("[%s] Duration: %.9f seconds", #func_call, elapsed); \
    _result; \
})
#else
#define SHOW_EXECUTION_TIME(func_call) (func_call)
#endif
LIB_INIT static void Initializer() {
    const char* env_val = getenv("TRACE");
    if(env_val) g_env.trace_level = atoi(env_val);
    debugln("Library initialized!\n");
}
LIB_DEINIT static void Deinitializer() {
    debugln("Library deinitialized!\n");
}
#if defined __WIN32__
BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    switch (reason) {
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
