// file.bpf.h
struct ssmap {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, __u32);
    __type(value, __u64);
};
// file1.bpf.c
#include "xdp_parse.h"
#include "file.bpf.h"
struct ssmap shared_map SEC(".maps"); // <--- Allocated here
SEC("xdp") int xdp_prog(struct xdp_md *ctx) {
    return XDP_PASS;
}
// file2.bpf.c
#include "xdp_parse.h"
#include "file.bpf.h"
extern struct ssmap shared_map; 
SEC("tc") int tc_prog(struct __sk_buff *skb) {
    return 0;
}
