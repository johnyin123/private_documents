#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/resource.h>
#include <bpf/libbpf.h>
#include "memory_skel.h"
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

int main(int argc, char *argv[])
{
    parse_command_line(argc, argv);
    if(strlen(env.bin) == 0)
        usage(argv[0]);

    struct memory_skel *skel;
    int err, i;
    long func_offset = 0x1135;
    /* nm /root/testprog  | grep foo */
    /* Set up libbpf errors and debug info callback */
    libbpf_set_print(libbpf_print_fn);
    /* Bump RLIMIT_MEMLOCK to allow BPF sub-system to do anything */
    bump_memlock_rlimit();
    /* Load and verify BPF application */
    if ((skel = memory_skel__open_and_load()) == NULL) {
        fprintf(stderr, "Failed to open and load BPF skeleton\n");
        return 1;
    }
    skel->links.uprobe = bpf_program__attach_uprobe(skel->progs.uprobe, false, -1, env.bin, func_offset);
    err = libbpf_get_error(skel->links.uprobe);
    if (err) {
        fprintf(stderr, "Failed to attach uprobe: %d\n", err);
        goto cleanup;
    }
    skel->links.uretprobe = bpf_program__attach_uprobe(skel->progs.uretprobe, true, -1, env.bin, func_offset);
    err = libbpf_get_error(skel->links.uretprobe);
    if (err) {
        fprintf(stderr, "Failed to attach uprobe: %d\n", err);
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
        /* trigger our BPF programs */
        fprintf(stderr, ".");
        sleep(1);
    }

cleanup:
    memory_skel__destroy(skel);
    return -err;
}
