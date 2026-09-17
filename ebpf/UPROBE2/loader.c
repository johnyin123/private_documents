#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/resource.h>
#include <bpf/libbpf.h>
#include "uprobe_skel.h"
#include <signal.h>

struct env {
    char bin[1024];
    int verbose;
} env = {
    .bin = {},
    .verbose = 0,
};

static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args)
{
    if (level == LIBBPF_DEBUG && !env.verbose)
        return 0;
    return vfprintf(stderr, format, args);
}

int bump_memlock_rlimit()
{
    struct rlimit rlim_new = {
        .rlim_cur = RLIM_INFINITY,
        .rlim_max = RLIM_INFINITY,
    };
    return setrlimit(RLIMIT_MEMLOCK, &rlim_new);
}

static volatile bool exiting;
static void int_exit(int sig)
{
    fprintf(stderr, "EXIT!!\n");
    exiting = 1;
}

#include <getopt.h>
const char *opt_short="b:hV";
struct option opt_long[] = {
    { "bin",     required_argument, NULL, 'b' }, 
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};
/*
 * { "demo",    required_argument, NULL, 'd' }, 
 * strncpy(env.demo, optarg, 10);
 * env.demo = strtol(optarg, NULL, 10);
*/

static void usage(char *prog)
{
    printf("Usage: %s\n", prog);
    printf("    -b|--bin <bin file>\n");
    printf("    -h|--help help\n");
    printf("    -V|--verbose\n");
    exit(0);
}

static int parse_command_line(int argc, char **argv)
{
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'b':
                strncpy(env.bin, optarg, sizeof(env.bin) - 1);
                break;
            case 'h':
                usage(argv[0]);
                return 0;
            case 'V':
                env.verbose = 1;
                break;
            default:
                usage(argv[0]);
                return 1;
        }
    }
    return 0;
}

int uprobed_add(int a, int b)
{
    return a + b;
}

int uprobed_sub(int a, int b)
{
    return a - b;
}

static void print_libbpf_ver() { 
    fprintf(stderr, "libbpf: %d.%d\n", libbpf_major_version(), libbpf_minor_version()); 
}

int main(int argc, char *argv[])
{
    parse_command_line(argc, argv);
    if(strlen(env.bin) == 0)
        usage(argv[0]);
    print_libbpf_ver();
    struct uprobe_skel *skel;
    int err, i;
    libbpf_set_print(libbpf_print_fn);
    bump_memlock_rlimit();
    if ((skel = uprobe_skel__open_and_load()) == NULL) {
        fprintf(stderr, "Failed to open and load BPF skeleton\n");
        return 1;
    }
	/* Let libbpf perform auto-attach for uprobe_sub/uretprobe_sub
	 * NOTICE: we provide path and symbol info in SEC for BPF programs
	 */
    if ((err = uprobe_skel__attach(skel))) {
        fprintf(stderr, "Failed to auto-attach BPF skeleton: %d\n", err);
        goto cleanup;
    }
    printf("Successfully started! Please run `cat /sys/kernel/debug/tracing/trace_pipe` "
           "to see output of the BPF programs.\n");
    signal(SIGINT, int_exit);
    signal(SIGHUP, int_exit);
    signal(SIGTERM, int_exit);
    for (i = 0; ; i++) {
        if (exiting) {
            break;
        }
        uprobed_add(i, i + 1);
        uprobed_sub(i * i, i);
        /* trigger our BPF programs */
        fprintf(stderr, ".");
        sleep(1);
    }
cleanup:
    uprobe_skel__destroy(skel);
    return -err;
}
