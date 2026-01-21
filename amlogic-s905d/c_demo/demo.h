#ifndef __DEMO_H_075432_3882714835__INC__
#define __DEMO_H_075432_3882714835__INC__
#ifdef __cplusplus
extern "C" {
#endif

#define BUILDING_LIBRARY
#if defined _WIN32 || defined __CYGWIN__
    #error "not impl!"
#elif defined __GNUC__
    #ifdef BUILDING_LIBRARY
        #define EXPORT_API __attribute__((visibility("default")))
    #else
        #define EXPORT_API extern
    #endif
#else
    #error "Unknown compiler or operating system"
#endif

#ifdef DEBUG
    #include <stdio.h>
    #define debugln(...) fprintf(stderr, __VA_ARGS__)
#else
    #define debugln(...) do {} while (0)
#endif

EXPORT_API int dllmain(int argc, char *argv[]);

#ifdef __cplusplus
}
#endif
#endif
