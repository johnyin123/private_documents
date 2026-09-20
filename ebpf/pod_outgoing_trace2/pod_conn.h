#ifndef __POD_DNS_H_090640_2684853615__INC__
#define __POD_DNS_H_090640_2684853615__INC__
#ifdef __cplusplus
extern "C" {
#endif
#include <linux/types.h>

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#define MAX_PAYLOAD_LEN 256 // Big enough to grab the whole DNS question structure
#define COMM_SIZE       16
struct raw_event {
    __u64 cgroup_id;
    __u32 pid;
    __u8  protocol;
    char comm[COMM_SIZE];
    __u32 saddr;
    __u32 daddr;
    __u16 sport;
    __u16 dport;
    __u16 payload_len;
    __u8 payload[MAX_PAYLOAD_LEN];
};
#ifndef min
#define min(x, y) ((x) < (y) ? (x) : (y))
#endif

#ifdef __cplusplus
}
#endif
#endif
