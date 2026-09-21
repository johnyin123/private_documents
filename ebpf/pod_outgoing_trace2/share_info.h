#ifndef __SHARE_INFO_H_124650_1827917275__INC__
#define __SHARE_INFO_H_124650_1827917275__INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#ifdef DEBUG
#define bpf_debug(fmt, ...) bpf_printk("DEBUG: " fmt, ##__VA_ARGS__)
#else
#define bpf_debug(fmt, ...) do { } while (0)
#endif

#ifndef UNUSED
#define UNUSED(x)           ((void)(x))
#endif
#ifndef ARRAY_LEN
#define ARRAY_LEN(a)        (sizeof(a)/sizeof((a)[0]))
#endif

#ifndef COMM_SIZE
#define COMM_SIZE           16
#endif
struct info {
    __u64 timestamp_ns;
    __u64 netns_cookie;
    int err;
    char comm[COMM_SIZE];
};
struct ssmap {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, __u64);   // Socket Cookie
    __type(value, struct info);
};

#ifdef __cplusplus
}
#endif
#endif
