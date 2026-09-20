#include <getopt.h>
#include <stdlib.h>
#include <signal.h>
#include "pod_conn_skel.h"
#include "pod_conn.h"
#include "loader.h"

struct env {
    int verbose;
    volatile bool exiting;
} env = {
    .verbose = LOG_ERR,
    .exiting = false,
};
const int *log_level = &env.verbose;
const char *opt_short="hV";
struct option opt_long[] = {
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -h|--help help\n"
        "    -V|--verbose\n"
        , prog);
    exit(0);
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
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
static void parse_dns_domain(const unsigned char *payload, __u32 payload_len, char *out_domain, size_t out_max) {
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
static int handle_conn_event(void *ctx, void *data, size_t data_sz) {
    UNUSED(ctx);
    char src[INET_ADDRSTRLEN], dst[INET_ADDRSTRLEN], domain[1024] = {};
    if (data_sz < sizeof(struct raw_event)) { return 0; }
    struct raw_event *e = data;
    ip_str_r(e->saddr, src, sizeof(src));
    ip_str_r(e->daddr, dst, sizeof(dst));
    switch (e->protocol) {
        case IPPROTO_UDP:
            if (e->dport == 53) {
                parse_dns_domain(e->payload, e->payload_len, domain, sizeof(domain));
            }
            fprintf(stderr, "U:%s, %s:%d=>%s:%d, cgid=%llu:%llu, pid=%d, QUERY=%s, len=%d\n",
                    e->comm, src, e->sport, dst, e->dport, e->cgroup_id, e->netns_cookie, e->pid, domain, e->payload_len);
            break;
        case IPPROTO_TCP:
            fprintf(stderr, "T:%s, %s:%d=>%s:%d, cgid=%llu:%llu, pid=%d, len=%d\n",
                    e->comm, src, e->sport, dst, e->dport, e->cgroup_id, e->netns_cookie, e->pid, e->payload_len);
            break;
    }
    return 0;
}
int main(int argc, char *argv[]) {
    struct ring_buffer *rb = NULL;
    parse_command_line(argc, argv);
    signal(SIGINT, sig_int);
    signal(SIGTERM, sig_int);
    /* Set up libbpf errors and debug info callback */
    if (env.verbose>=LOG_DEBUG) { print_libbpf_ver(); libbpf_set_print(libbpf_print_fn); }
    else { libbpf_set_print(NULL); }
    if (bump_memlock_rlimit()) { log_error("Failed setrlimit: %d, %s", errno, strerror(errno)); return 1; }
    /* 1. 打开 skeleton */
    struct pod_conn *skel = pod_conn__open();
    if (!skel) {
        log_error("Failed to open BPF skeleton");
        return 1;
    }
    /* 2. 加载到内核 */
    int err = pod_conn__load(skel);
    if (err) {
        log_error("Failed to load BPF skeleton: %d, %s", err, strerror(errno));
        goto cleanup;
    }
    /* 3. Attach directly via native cgroup structural tracking anchors*/
    if (!(skel->links.trace_sockops = attach_cgroup(skel->progs.trace_sockops, "/sys/fs/cgroup"))) { goto cleanup; }
    if (!(skel->links.track_connect4 = attach_cgroup(skel->progs.track_connect4, "/sys/fs/cgroup"))) { goto cleanup; }
    if (!(skel->links.trace_conn = attach_cgroup(skel->progs.trace_conn, "/sys/fs/cgroup"))) { goto cleanup; }
    /* 4. ringbuffer*/
    if (!(rb = ring_buffer__new(bpf_map__fd(skel->maps.event_rb), handle_conn_event, NULL, NULL))) {
        log_error("Failed to create ring buffer");
        goto cleanup;
    }
    /* 5. 保持运行，信号触发退出 */
    fprintf(stderr, "Press Ctrl+C to stop and detach...\n");
    while (!env.exiting) {
        err = ring_buffer__poll(rb, 100 /* timeout ms */);
        if (err < 0 && err != -EINTR) {
            log_error("Error polling ring buffer: %d", err);
            break;
        }
    }
    log_info("Detaching bpf program...");
cleanup:
    if (rb) { ring_buffer__free(rb); }
    pod_conn__destroy(skel);
    return err < 0 ? 1 : 0;
}
