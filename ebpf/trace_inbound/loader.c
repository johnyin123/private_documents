#include <stdio.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/resource.h>

#include <net/if.h>
#include <arpa/inet.h>
#include <linux/if_link.h>

#include <bpf/libbpf.h>
#include "trace_conn_skel.h"
#include "trace_conn.h"

#define UNUSED(x)     ((void)(x))
#define ARRAY_LEN(a)  (sizeof(a)/sizeof((a)[0]))

struct env {
    char ifname[IF_NAMESIZE];
    int verbose;
} env = {
    .ifname = { 0 },
    .verbose = 3,
};
enum { LOG_EMERG=0, LOG_ALERT=1, LOG_CRIT=2, LOG_ERR=3, LOG_WARNING=4, LOG_NOTICE=5, LOG_INFO=6, LOG_DEBUG=7 };
#define log_debug(fmt,args...)  { if(env.verbose>=LOG_DEBUG) fprintf(stderr, "DEBUG %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_info(fmt,args...)   { if(env.verbose>=LOG_INFO)  fprintf(stderr, "INFO  %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_error(fmt,args...)  { if(env.verbose>=LOG_ERR)   fprintf(stderr, "ERROR %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
const char *opt_short="hVi:";
struct option opt_long[] = {
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -i  * <ifname>    attach network device name\n"
        "    -h|--help help\n"
        "    -V|--verbose\n"
        "Example:\n"
        "  %s -i eth0\n"
        , prog, prog);
    exit(0);
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'i':
                snprintf(env.ifname, ARRAY_LEN(env.ifname), "%s", optarg);
                break;
            case 'h':
                usage(argv[0]);
                return 0;
            case 'V':
                env.verbose++;
                break;
            default:
                usage(argv[0]);
                return 1;
        }
    }
    return 0;
}
static volatile bool exiting = false;
static void sig_int(int signo) {
    UNUSED(signo);
    exiting = true;
}
static void print_libbpf_ver() { 
    log_debug("libbpf: %d.%d", libbpf_major_version(), libbpf_minor_version()); 
}
static int bump_memlock_rlimit() {
    struct rlimit rlim_new = {
        .rlim_cur = RLIM_INFINITY,
        .rlim_max = RLIM_INFINITY,
    };
    return setrlimit(RLIMIT_MEMLOCK, &rlim_new);
}
static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args) {
    if (level == LIBBPF_DEBUG && env.verbose<LOG_DEBUG)
        return 0;
    return vfprintf(stderr, format, args);
}
/* Ringbuf 回调：打印新连接 */
static int handle_event(void *ctx, void *data, size_t data_sz) {
    UNUSED(ctx); UNUSED(data_sz);
    struct connection_key *e = data;
    char src_str[INET_ADDRSTRLEN], dst_str[INET_ADDRSTRLEN];
    struct in_addr saddr = { .s_addr = e->saddr };
    struct in_addr daddr = { .s_addr = e->daddr };
    inet_ntop(AF_INET, &saddr, src_str, sizeof(src_str));
    inet_ntop(AF_INET, &daddr, dst_str, sizeof(dst_str));
    fprintf(stderr, "NEW %s:%u -> %s:%u\n", src_str, ntohs(e->sport), dst_str, ntohs(e->dport));
    return 0;
}
int main(int argc, char *argv[]) {
    struct ring_buffer *rb = NULL;
    parse_command_line(argc, argv);
    if (strlen(env.ifname) == 0) {
        log_error("interface name is required.");
        usage(argv[0]);
        return 1;
    }
    signal(SIGINT, sig_int);
    signal(SIGTERM, sig_int);
    print_libbpf_ver();
    /* Set up libbpf errors and debug info callback */
    if (env.verbose>=LOG_DEBUG) { libbpf_set_print(libbpf_print_fn); }
    else { libbpf_set_print(NULL); }
    bump_memlock_rlimit();
    int ifindex = if_nametoindex(env.ifname);
    if (ifindex == 0) {
        log_error("invalid interface %s: %s", env.ifname, strerror(errno));
        return 1;
    }
    /* 1. 打开 skeleton */
    struct trace_conn *skel = trace_conn__open();
    if (!skel) {
        log_error("Failed to open BPF skeleton");
        return 1;
    }
    /* 2. 加载到内核 */
    int err = trace_conn__load(skel);
    if (err) {
        log_error("Failed to load BPF skeleton: %d", err);
        goto cleanup;
    }
    /* 3. 附加到网卡（libbpf 自动尝试驱动模式，失败则回退到 skb 通用模式） */
    skel->links.xdp_prog = bpf_program__attach_xdp(skel->progs.xdp_prog, ifindex);
    if (!skel->links.xdp_prog) {
        err = -errno;
        log_error("Failed to attach XDP to %s: %d", env.ifname, err);
        goto cleanup;
    }
    log_info("XDP loaded on %s (ifindex=%d)", env.ifname, ifindex);
    /* 4. 创建 ringbuf 轮询 */
    rb = ring_buffer__new(bpf_map__fd(skel->maps.events_ringbuf), handle_event, NULL, NULL);
    if (!rb) {
        log_error("Failed to create ring buffer");
        goto cleanup;
    }
    fprintf(stderr, "Press Ctrl+C to stop and detach...\n");
    /* 5. 保持运行，信号触发退出 */
    struct data_stats stats;
    while (!exiting) {
        err = ring_buffer__poll(rb, 100 /* timeout ms */);
        if (err == -EINTR)
            break;
        if (err < 0) {
            log_error("Error polling ring buffer: %d", err);
            break;
        }
        __u32 array_idx = 0;
        if (0 == bpf_map__lookup_elem(skel->maps.traffic_map, &array_idx, sizeof(array_idx), &stats, sizeof(stats), 0))
            log_info("total income: %-15llu", stats.in_cnt);
    }
    log_info("Detaching XDP program...");
cleanup:
    ring_buffer__free(rb);
    trace_conn__destroy(skel);
    return err < 0 ? 1 : 0;
}
