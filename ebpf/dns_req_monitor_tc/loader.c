#include <getopt.h>
#include <stdlib.h>
#include <signal.h>
#include "udp_dump_skel.h"
#include "udp_dump.h"
#include "loader.h"

#define DIR_FLOW      BPF_TC_EGRESS /*BPF_TC_INGRESS*/
#define MAX_IFACES    128
struct env {
    unsigned int ifindex[MAX_IFACES];
    int verbose;
    volatile bool exiting;
} env = {
    .ifindex = {0},
    .verbose = LOG_ERR,
    .exiting = false,
};
const int *log_level = &env.verbose;
const char *opt_short="hVi:";
struct option opt_long[] = {
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -i  *   <ifname>\n"
        "    -h|--help help\n"
        "    -V|--verbose\n"
        , prog);
    exit(0);
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'i':
                if(!add_interface(optarg, env.ifindex, ARRAY_LEN(env.ifindex))) { usage(argv[0]); }
                break;
            case 'h':
                usage(argv[0]);
                break;
            case 'V':
                env.verbose++;
                break;
            default:
                usage(argv[0]);
        }
    }
    return 0;
}
static void sig_int(int signo) {
    UNUSED(signo);
    env.exiting = true;
}
void parse_dns_domain(const unsigned char *payload, __u32 payload_len, char *out_domain, size_t out_max) {
    __u32 idx = 12; // Start parsing right after the 12-byte standard DNS Header
    __u32 out_idx = 0;
    if (payload_len <= 12) {
        snprintf(out_domain, out_max, "<malformed packet>");
        return;
    }
    while (idx < payload_len && out_idx < (out_max - 1)) {
        __u8 label_len = payload[idx];
        // \x00 indicates the end of the query layout string
        if (label_len == 0) {
            break;
        }
        // Handle compression pointer flags safely (0xc0)
        if ((label_len & 0xC0) == 0xC0) {
            // In pure requests compression pointers are rare, but handle safely by stopping
            break;
        }
        idx++; // Advance past the length byte
        // Read characters belonging to the current label segment
        for (__u8 i = 0; i < label_len && idx < payload_len && out_idx < (out_max - 1); i++) {
            out_domain[out_idx++] = payload[idx++];
        }
        // Append delimiter dots between domain zones
        if (idx < payload_len && payload[idx] != 0 && out_idx < (out_max - 1)) {
            out_domain[out_idx++] = '.';
        }
    }
    out_domain[out_idx] = '\0'; // Seal string boundary safely
    if (out_idx == 0) {
        snprintf(out_domain, out_max, "<unknown>");
    }
}
#include <arpa/inet.h>
void handle_event(void *ctx, int cpu, void *data, __u32 data_sz) {
    UNUSED(ctx);
    struct dns_raw_event *e = data;
    if (data_sz < sizeof(*e)) {
        fprintf(stderr, "short event: %u bytes\n", data_sz);
        return;
    }
    char src[INET_ADDRSTRLEN], dst[INET_ADDRSTRLEN];
    char domain[1024] = {0};
    inet_ntop(AF_INET, &e->saddr, src, sizeof(src));
    inet_ntop(AF_INET, &e->daddr, dst, sizeof(dst));
    parse_dns_domain(e->payload, e->payload_len, domain, sizeof(domain));
    fprintf(stderr, "[CPU %d] pid = %d cgroup = %lld [%d] %s:%u -> %s:%u payload=%u QUERY=%s\n", cpu, e->pid, e->cgroup_id, e->ifindex, src, e->sport, dst, e->dport, e->payload_len, domain);
}
void handle_lost(void *ctx, int cpu, __u64 lost_cnt) {
    UNUSED(ctx);
    fprintf(stderr, "lost %llu events on CPU #%d\n", lost_cnt, cpu);
}
int main(int argc, char *argv[]) {
    struct perf_buffer *pb = NULL;
    parse_command_line(argc, argv);
    if (env.ifindex[0] == 0) { usage(argv[0]); }
    signal(SIGINT, sig_int);
    signal(SIGTERM, sig_int);
    /* Set up libbpf errors and debug info callback */
    if (env.verbose>=LOG_DEBUG) { print_libbpf_ver(); libbpf_set_print(libbpf_print_fn); }
    else { libbpf_set_print(NULL); }
    if (bump_memlock_rlimit()) { log_error("Failed setrlimit: %d, %s", errno, strerror(errno)); return 1; }
    /* 1. 打开 skeleton */
    struct udp_dump *skel = udp_dump__open();
    if (!skel) {
        log_error("Failed to open BPF skeleton");
        return 1;
    }
    /* 2. 加载到内核 */
    int err = udp_dump__load(skel);
    if (err) {
        log_error("Failed to load BPF skeleton: %d, %s", err, strerror(errno));
        goto cleanup;
    }
    /* 2.1 attach cgroup/sock */
    if (!(skel->links.track_connect4 = attach_cgroup(skel->progs.track_connect4, "/sys/fs/cgroup"))) { goto cleanup; }
    /* 3. Attach directly via native cgroup structural tracking anchors*/
    for (unsigned int i=0; i<ARRAY_LEN(env.ifindex); i++) {
        if (env.ifindex[i] == 0) { break; }
        if (!(skel->links.handle_ingress = attach_tc(skel->progs.handle_ingress, env.ifindex[i]))) { goto cleanup; }
        if (!(skel->links.handle_egress = attach_tc(skel->progs.handle_egress, env.ifindex[i]))) { goto cleanup; }
        log_info("TC attached: ifindex=%u", env.ifindex[i]);
    }
    /* 4. perf_buffer*/
    if (!(pb = perf_buffer__new(bpf_map__fd(skel->maps.events), 64, handle_event, handle_lost, NULL, NULL))) {
        err = -errno;
        log_error("perf_buffer__new failed: %s", strerror(errno));
        goto cleanup;
    }
    /* 5. 保持运行，信号触发退出 */
    fprintf(stderr, "Press Ctrl+C to stop and detach...\n");
    while (!env.exiting) {
        err = perf_buffer__poll(pb, 100);
        if (err < 0 && err != -EINTR) {
            log_error("Error polling perf buffer: %d", err);
            break;
        }
    }
    log_info("Detaching bpf program...");
cleanup:
    if (pb) { perf_buffer__free(pb); }
    udp_dump__destroy(skel);
    return err < 0 ? 1 : 0;
}
