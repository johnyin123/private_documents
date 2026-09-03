#ifndef __POD_TRACE_H_102751_1089307862__INC__
#define __POD_TRACE_H_102751_1089307862__INC__
#ifdef __cplusplus
extern "C" {
#endif

struct event {
    __u64 cgroup_id;
    __u32 pid;
    __u16 protocol;
    __u32 daddr;
    __u16 dport;
    __u32 saddr;
    __u16 sport;
    __u64 time_consuming;
    int final_errno;
    char comm[16];
};

#ifdef __cplusplus
}
#endif
#endif
