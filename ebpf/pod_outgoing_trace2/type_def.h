#ifndef __TYPE_DEF_H_162722_753519854__INC__
#define __TYPE_DEF_H_162722_753519854__INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#ifndef MAX_PAYLOAD_LEN
#define MAX_PAYLOAD_LEN 256 // Big enough to grab the whole DNS question structure
#endif
#ifndef COMM_SIZE
#define COMM_SIZE           16
#endif

struct raw_event {
    __u64 cgroup_id;
    __u64 netns_cookie;
    __u32 pid;
    __u8  protocol;
    int err;
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
