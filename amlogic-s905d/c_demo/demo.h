#ifndef __DEMO_H_075432_3882714835__INC__
#define __DEMO_H_075432_3882714835__INC__
#ifdef __cplusplus
extern "C" {
#endif

#if defined __WIN32__ || defined __CYGWIN__
    #define LIB_INIT
    #define LIB_DEINIT
    #ifdef BUILDING_LIBRARY
        #define EXPORT_API __declspec(dllexport)
    #else
        #define EXPORT_API __declspec(dllimport)
    #endif
#elif defined __GNUC__
    #ifdef BUILDING_LIBRARY
        #define EXPORT_API __attribute__((visibility("default")))
        #define LIB_INIT   __attribute__((constructor))
        #define LIB_DEINIT __attribute__((destructor))
    #else
        #define EXPORT_API extern
        #define LIB_INIT
        #define LIB_DEINIT
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
LIB_INIT void Initializer();
LIB_DEINIT void Deinitializer();

#ifdef __cplusplus
}
#endif
#endif
