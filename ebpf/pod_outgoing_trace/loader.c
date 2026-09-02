#include <stdio.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/resource.h>

#include <bpf/libbpf.h>
#include "pod_trace_skel.h"
#include "pod_trace.h"

#define UNUSED(x)     ((void)(x))
#define ARRAY_LEN(a)  (sizeof(a)/sizeof((a)[0]))
#define PIN_PATH      "/sys/fs/bpf/pod_trace_link"
#define PIN_PATH_RET  "/sys/fs/bpf/pod_trace_ret_link"

struct env {
    int persist;
    int verbose;
    volatile bool exiting;
} env = {
    .persist = 0,
    .verbose = 3,
    .exiting = false,
};
enum { LOG_EMERG=0, LOG_ALERT=1, LOG_CRIT=2, LOG_ERR=3, LOG_WARNING=4, LOG_NOTICE=5, LOG_INFO=6, LOG_DEBUG=7 };
#define log_debug(fmt,args...)  { if(env.verbose>=LOG_DEBUG) fprintf(stderr, "DEBUG %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_info(fmt,args...)   { if(env.verbose>=LOG_INFO)  fprintf(stderr, "INFO  %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_error(fmt,args...)  { if(env.verbose>=LOG_ERR)   fprintf(stderr, "ERROR %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
const char *opt_short="hVP";
struct option opt_long[] = {
    { "persist", no_argument, NULL, 'P' },
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -P|--persist      persistent ebpf when exit\n"
        "    -h|--help help\n"
        "    -V|--verbose\n"
        , prog);
    exit(0);
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'P':
                env.persist = 1;
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
static void print_libbpf_ver() { 
    log_debug("libbpf: %d.%d", libbpf_major_version(), libbpf_minor_version()); 
}
static int bump_memlock_rlimit() {
    struct rlimit rlim_new = { .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY, };
    return setrlimit(RLIMIT_MEMLOCK, &rlim_new);
}
static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args) {
    if (level == LIBBPF_DEBUG && env.verbose<LOG_DEBUG)
        return 0;
    return vfprintf(stderr, format, args);
}
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
static void resolve_cgroup_id_to_pod(__u64 target_id, char *out_path, const char *base_dir) {
    DIR *dir = opendir(base_dir);
    if (!dir) return;
    struct dirent *entry;
    char path[1024];
    while ((entry = readdir(dir))) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        if (entry->d_type != DT_DIR) continue;
        snprintf(path, sizeof(path), "%s/%s", base_dir, entry->d_name);
        // Check this directory's inner identifier handle
        struct stat st;
        if (stat(path, &st) == 0 && (unsigned long long)st.st_ino == target_id) {
            // Found it! Extract Kuberenetes metadata context out of the path string
            // Path structure example: .../kubepods.slice/kubepods-pod<POD_UID>.slice/
            strcpy(out_path, path);
            closedir(dir);
            return;
        }
        // Recurse deeper into the cgroup sub-tree
        resolve_cgroup_id_to_pod(target_id, out_path, path);
    }
    closedir(dir);
}
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
const char *ip_str(in_addr_t addr) {
    static __thread char buf[INET_ADDRSTRLEN];
    struct in_addr ip = { .s_addr = addr };
    if (inet_ntop(AF_INET, &ip, buf, sizeof(buf)) == NULL)
        return "<invalid>";
    return buf;
}
static int handle_event(void *ctx, void *data, size_t data_sz) {
    UNUSED(ctx); UNUSED(data_sz);
    const struct event *e = data;
    char pod_resolved_identity[1024] = "Host / Non-K8s Process";
    resolve_cgroup_id_to_pod(e->cgroup_id, pod_resolved_identity, "/sys/fs/cgroup");
    fprintf(stderr, "[Cgroup ID: %llu]\n", e->cgroup_id);
    fprintf(stderr, " ├─ Location: %s\n", pod_resolved_identity);
    fprintf(stderr, " └─ Traffic:  %s (PID: %d) -> %s:%d\n", e->comm, e->pid, ip_str(e->daddr), ntohs(e->dport));
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
    bump_memlock_rlimit();
    /* 1. 打开 skeleton */
    struct pod_trace *skel = pod_trace__open();
    if (!skel) {
        log_error("Failed to open BPF skeleton");
        return 1;
    }
    /* 2. 加载到内核 */
    int err = pod_trace__load(skel);
    if (err) {
        log_error("Failed to load BPF skeleton: %d, %s", err, strerror(errno));
        goto cleanup;
    }
    /* 3. attach*/
    struct bpf_link *link = bpf_link__open(PIN_PATH);
    struct bpf_link *link_ret = bpf_link__open(PIN_PATH_RET);
    if ((link) && (link_ret)) {
        log_info("Found an existing pinned bpf link. Reusing it.");
        skel->links.tcp_v4_connect = link;
        skel->links.tcp_v4_connect_exit = link_ret;
    } else {
        skel->links.tcp_v4_connect = bpf_program__attach(skel->progs.tcp_v4_connect);
        if (!skel->links.tcp_v4_connect) {
            log_error("Failed to attach bpf: %d, %s", err, strerror(errno));
            goto cleanup;
        }
        skel->links.tcp_v4_connect_exit = bpf_program__attach(skel->progs.tcp_v4_connect_exit);
        if (!skel->links.tcp_v4_connect_exit) {
            log_error("Failed to attach bpf: %d, %s", err, strerror(errno));
            goto cleanup;
        }
        if (env.persist) {
            log_info("Pin the link to the BPF filesystem");
            err = bpf_link__pin(skel->links.tcp_v4_connect, PIN_PATH);
            if (err) {
                log_error("Failed to pin link to %s: %d", PIN_PATH, err);
                goto cleanup;
            }
            err = bpf_link__pin(skel->links.tcp_v4_connect_exit, PIN_PATH_RET);
            if (err) {
                log_error("Failed to pin link to %s: %d", PIN_PATH_RET, err);
                goto cleanup;
            }
        }
    }
    /* 4. 创建 ringbuf 轮询 */
    rb = ring_buffer__new(bpf_map__fd(skel->maps.rb), handle_event, NULL, NULL);
    if (!rb) {
        log_error("Failed to create ring buffer");
        goto cleanup;
    }
    //dump_config_map(skel->maps.config_map);
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
    pod_trace__destroy(skel);
    return err < 0 ? 1 : 0;
}
