#ifndef __BPF_SOCKOPS_0918314d_b66f_4d49_9bcf_c27d776c5fbf
#define __BPF_SOCKOPS_0918314d_b66f_4d49_9bcf_c27d776c5fbf

#ifndef FORCE_READ
#define FORCE_READ(X) (*(volatile typeof(X)*)&X)
#endif

#ifndef bpf_printk
/* msg in /sys/kernel/debug/tracing/trace_pipe */
#define bpf_printk(fmt, ...)                                         \
	({                                                              \
		char ____fmt[] = fmt;                                       \
		bpf_trace_printk(____fmt, sizeof(____fmt), ##__VA_ARGS__);  \
	})
#endif

struct sock_key {
	uint32_t sip4;
	uint32_t dip4;
	uint8_t  family;
	uint8_t  pad1;
	uint16_t pad2;
	// this padding required for 64bit alignment
	// else ebpf kernel verifier rejects loading
	// of the program
	uint32_t pad3;
	uint32_t sport;
	uint32_t dport;
} __attribute__((packed));


struct {
	__uint(type, BPF_MAP_TYPE_SOCKHASH);
	__uint(key_size, sizeof(struct sock_key));
	__uint(value_size, sizeof(int));
	__uint(max_entries, 65535);
} sock_ops_map SEC(".maps");
#endif
