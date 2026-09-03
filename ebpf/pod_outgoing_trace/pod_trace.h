#ifndef __POD_TRACE_H_102751_1089307862__INC__
#define __POD_TRACE_H_102751_1089307862__INC__
#ifdef __cplusplus
extern "C" {
#endif

struct event {
    __u64 cgroup_id;
    __u32 pid;
    __u32 daddr;
    __u16 dport;
    int final_errno;
    char comm[16];
};

#ifdef __cplusplus
}
#endif
#endif
