#ifndef __XDP_STATS_H_095433_2532782785__INC__
#define __XDP_STATS_H_095433_2532782785__INC__
#include "xdp_stats_def.h"

struct record {
    __u64 timestamp;
    struct datarec total;
};

struct stats_record {
    struct record stats[XDP_ACTION_MAX];
};

void stats_collect(int map_fd, __u32 map_type, struct stats_record *stats_rec);
double calc_period(struct record *r, struct record *p);

static inline const char *action2str(enum xdp_action action)
{
    switch (action) {
        case XDP_ABORTED: return "XDP_ABORTED";
        case XDP_DROP: return "XDP_DROP";
        case XDP_PASS: return "XDP_PASS";
        case XDP_TX: return "XDP_TX";
        case XDP_REDIRECT: return "XDP_REDIRECT";
        default: return NULL;
    }
}

#include <bpf/libbpf.h>
static inline void print_libbpf_ver() { 
    fprintf(stderr, "libbpf: %d.%d\n", libbpf_major_version(), libbpf_minor_version()); 
}

#include <sys/time.h>
#include <sys/resource.h>
static inline int bump_memlock_rlimit()
{
    struct rlimit rlim_new = {
        .rlim_cur = RLIM_INFINITY,
        .rlim_max = RLIM_INFINITY,
    };
    return setrlimit(RLIMIT_MEMLOCK, &rlim_new);
}
#endif
