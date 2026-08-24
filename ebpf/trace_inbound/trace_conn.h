#ifndef __TRACE_CONN_H_141516_798858120__INC__
#define __TRACE_CONN_H_141516_798858120__INC__
#ifdef __cplusplus
extern "C" {
#endif

#include <linux/types.h>
struct data_stats {
    __u64 in_cnt;
};
struct connection_key {
    __u32 saddr;
    __u32 daddr;
    __u16 sport;
    __u16 dport;
};

#ifdef __cplusplus
}
#endif
#endif
