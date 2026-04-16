#include <stdlib.h>
#include <stdio.h>
#include <errno.h>

#if defined __WIN32__ || defined __CYGWIN__
#include <Windows.h>
#define OPEN(file)          LoadLibraryA(file)
#define CLOSE(handle)       FreeLibrary(handle)
#define SYM(handle, symbol) GetProcAddress(handle, symbol)
#define ERR                 GetLastError()
#else
#include <dlfcn.h>
#define OPEN(file)          dlopen(file, RTLD_LAZY) /* Enable LAZY mode as default */
#define CLOSE(handle)       dlclose(handle)
#define SYM(handle, symbol) dlsym(handle, symbol)
#define ERR                 dlerror()
#endif

static inline void *dl_module_open(const char* file) {
    return OPEN(file);
}
static inline void *dl_module_symbol(void *module, const char* symbol) {
    return SYM(module, symbol);
}
static inline int dl_module_close(void *module) {
    return CLOSE(module);
}
static inline const char *dl_get_error() {
#if defined (_WIN32) && !defined (__CYGWIN__)
    static char buff[64];
    int code = ERR;
    if(!code) return NULL;
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), buff, sizeof(buff), NULL);
    return buff;
#else
    return ERR;
#endif
}

int main(int argc, char **argv) {
    typedef int (*func)();
    const char *mod_name = "./libHeaSecReadInfo.x86_64.so";
    void * module = dl_module_open(mod_name);
    if(!module) {
        fprintf(stderr, "Error loading main.mod: %s\n", dl_get_error());
        return 1;
    }
    func module_main = (func)dl_module_symbol(module, "TestingFun");
    if (!module_main) {
        fprintf(stderr, "module_main() not found: %s\n", dl_get_error());
        dl_module_close(module);
        return 1;
    }
    module_main();
    dl_module_close(module);
    return 0;
}
