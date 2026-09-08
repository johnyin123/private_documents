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
#include "xdp_masq_skel.h"
#include "xdp_masq.h"

#define UNUSED(x)     ((void)(x))
#define ARRAY_LEN(a)  (sizeof(a)/sizeof((a)[0]))
#define PIN_PATH      "/sys/fs/bpf/xdp_masq_link"

struct env {
    char ifname[IF_NAMESIZE];
    __be32 public_ip;
    int persist;
    int verbose;
    volatile bool exiting;
} env = {
    .ifname = { 0 },
    .public_ip = INADDR_NONE,
    .persist = 0,
    .verbose = 3,
    .exiting = false,
};
enum { LOG_EMERG=0, LOG_ALERT=1, LOG_CRIT=2, LOG_ERR=3, LOG_WARNING=4, LOG_NOTICE=5, LOG_INFO=6, LOG_DEBUG=7 };
#define log_debug(fmt,args...)  { if(env.verbose>=LOG_DEBUG) fprintf(stderr, "DEBUG %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_info(fmt,args...)   { if(env.verbose>=LOG_INFO)  fprintf(stderr, "INFO  %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_error(fmt,args...)  { if(env.verbose>=LOG_ERR)   fprintf(stderr, "ERROR %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
const char *opt_short="hVi:a:P";
struct option opt_long[] = {
    { "persist", no_argument, NULL, 'P' },
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -i  * <ifname>    attach network device name\n"
        "    -a  * <ipaddr>    public ipaddr\n"
        "    -P|--persist      persistent ebpf when exit\n"
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
            case 'a':
                env.public_ip = inet_addr(optarg);
                break;
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
int main(int argc, char *argv[]) {
    parse_command_line(argc, argv);
    if ((strlen(env.ifname) == 0) || (INADDR_NONE == env.public_ip)) {
        log_error("required args");
        usage(argv[0]);
    }
    signal(SIGINT, sig_int);
    signal(SIGTERM, sig_int);
    /* Set up libbpf errors and debug info callback */
    if (env.verbose>=LOG_DEBUG) { print_libbpf_ver(); libbpf_set_print(libbpf_print_fn); }
    else { libbpf_set_print(NULL); }
    bump_memlock_rlimit();
    int ifindex = if_nametoindex(env.ifname);
    if (ifindex == 0) {
        log_error("invalid interface %s: %s", env.ifname, strerror(errno));
        return 1;
    }
    /* 1. 打开 skeleton */
    struct xdp_masq *skel = xdp_masq__open();
    if (!skel) {
        log_error("Failed to open BPF skeleton");
        return 1;
    }
    skel->bss->public_ip = env.public_ip;
    /* 2. 加载到内核 */
    int err = xdp_masq__load(skel);
    if (err) {
        log_error("Failed to load BPF skeleton: %d, %s", err, strerror(errno));
        goto cleanup;
    }
    /* 3. 附加到网卡（libbpf 自动尝试驱动模式，失败则回退到 skb 通用模式） */
    struct bpf_link *link = bpf_link__open(PIN_PATH);
    if (link) {
        log_info("Found an existing pinned bpf link. Reusing it.");
        skel->links.xdp_nat_engine = link;
    } else {
        skel->links.xdp_nat_engine = bpf_program__attach_xdp(skel->progs.xdp_nat_engine, ifindex);
        if (!skel->links.xdp_nat_engine) {
            err = -errno;
            log_error("Failed to attach bpf: %d, %s", err, strerror(errno));
            goto cleanup;
        }
        if (env.persist) {
            log_info("Pin the link to the BPF filesystem");
            err = bpf_link__pin(skel->links.xdp_nat_engine, PIN_PATH);
            if (err) {
                log_error("Failed to pin link to %s: %d", PIN_PATH, err);
                goto cleanup;
            }
        }
    }
    log_info("XDP loaded on %s (ifindex=%d)", env.ifname, ifindex);
    /* 4. set  config_map */
    /* 5. 保持运行，信号触发退出 */
    fprintf(stderr, "Press Ctrl+C to stop and detach...\n");
    while (!env.exiting) {
        sleep(1);
    }
    log_info("Detaching bpf program...");
cleanup:
    xdp_masq__destroy(skel);
    return err < 0 ? 1 : 0;
}
