#ifndef __XDP_LB_H_115311_676520999__INC__
#define __XDP_LB_H_115311_676520999__INC__
#ifdef __cplusplus
extern "C" {
#endif
#include <linux/types.h>
#include <linux/if_ether.h>
struct key {
    __be32 ip_addr;
    __u16 port;
}__attribute__((packed)); /*avoid  bpf_map_lookup_elem key has padding char, and not found*/
#define MAX_PEERS  4  // 2, 4, 8, 16, 32. MUST power of 2
struct backend_config {
    struct{
        __be32 ip_addr;
        __u16 port;
        unsigned char mac_addr[ETH_ALEN];
    } vip;
    __u16 num;
    struct {
        __be32 ip_addr;
        unsigned char mac_addr[ETH_ALEN];
    } backends[MAX_PEERS];
};
struct flow_5tuple {
    __u32 saddr, daddr;
    __u16 sport, dport;
    __u8  protocol;
    __u8  padding[3];
};
#define MAX_CONF_ENTRIES  16

#ifdef __cplusplus
}
#endif
#endif
