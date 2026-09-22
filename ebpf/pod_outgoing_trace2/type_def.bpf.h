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
#include "type_def.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_endian.h>

struct info {
    __u64 dualtime_ns;
    __u64 netns_cookie;
    __u64 cgroup_id;
    __u32 pid;
    int err;
    char comm[COMM_SIZE];
};
struct ssmap {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, __u64);   // Socket Cookie
    __type(value, struct info);
};
struct event_ring {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 16);
};

#ifdef __cplusplus
}
#endif
#endif
