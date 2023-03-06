#define SAMPLE_SIZE 1024ul
#define MAX_CPUS 128

#define min(x, y) ((x) < (y) ? (x) : (y))
/* Metadata will be in the perf event before the packet data. */
struct data_t {
    __u16 cookie;
    __u16 pkt_len;
} __attribute__((packed));


