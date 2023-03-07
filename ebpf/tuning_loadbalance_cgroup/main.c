#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <time.h>
#include <bpf/bpf.h>
#include "sockops_skel.h"
#include "sockredir_skel.h"

static volatile bool exiting;
struct env {
    bool detach;
    bool verbose;
} env = {
    .detach = false,
    .verbose = 0,
};
static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args)
{
    if (level == LIBBPF_DEBUG && !env.verbose)
        return 0;
    return vfprintf(stderr, format, args);
}

static int bump_memlock_rlimit()
{
    struct rlimit rlim_new = {
        .rlim_cur = RLIM_INFINITY,
        .rlim_max = RLIM_INFINITY,
    };
    return setrlimit(RLIMIT_MEMLOCK, &rlim_new);
}

#include <getopt.h>
const char *opt_short="dhV";
struct option opt_long[] = {
    { "detach",  no_argument, NULL, 'd' },
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};

static void usage(char *prog)
{
    printf("Usage: %s\n", prog);
    printf("    -d|--detach detach\n");
    printf("    -h|--help help\n");
    printf("    -V|--verbose\n");
    exit(0);
}

static int parse_command_line(int argc, char **argv)
{
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'd':
                env.detach = true;
                return 0;
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
#include <signal.h>
static void int_exit(int sig)
{
    fprintf(stderr, "EXIT!!\n");
    exiting = 1;
}

#include <sys/stat.h>
#include <fcntl.h>
int main(int argc, char **argv)
{
    struct sockops_skel *skel = NULL;
    struct bpf_link *link = NULL;
    int err;
    parse_command_line(argc, argv);

    libbpf_set_print(libbpf_print_fn);
    if ((err = bump_memlock_rlimit())) {
        fprintf(stderr, "Failed to increase rlimit: %d", err);
        return 1;
    }
    signal(SIGINT, int_exit);
    signal(SIGHUP, int_exit);
    signal(SIGTERM, int_exit);
    /* Load and verify BPF programs*/
    if (!(skel = sockops_skel__open_and_load())) {
        fprintf(stderr, "Failed to open and load BPF skeleton\n");
        return 2;
    }
    int cg_fd = open("/sys/fs/cgroup/sockredir", O_DIRECTORY | O_RDONLY);
    if (cg_fd < 0) {
        fprintf(stderr, "Failed to open cgroup path: '%s'\n", strerror(errno));
        return EXIT_FAILURE;
    }
    if (env.detach) {
        enum bpf_attach_type type = BPF_CGROUP_INET_SOCK_CREATE;
        // enum bpf_attach_type type = BPF_CGROUP_INET_INGRESS;
        // type = BPF_CGROUP_INET_EGRESS;
        if((err = bpf_prog_detach(cg_fd, type)) < 0) {
            fprintf(stderr, "bpf_prog_detach() returned '%s' (%d) %d\n", strerror(errno), errno, err);
        }
        goto cleanup;
    }
    link = bpf_program__attach_cgroup(skel->progs.bpf_sockops, cg_fd);
    if (libbpf_get_error(link)) {
        fprintf(stderr, "ERROR: bpf_program__attach failed\n");
        link = NULL;
        goto cleanup;
    }
    if ((err = bpf_map__pin(skel->maps.sock_ops_map, "/sys/fs/bpf/sock_ops_map")) < 0) {
        fprintf(stderr, "ERROR: bpf_map__pin failed: %d\n", err);
        goto cleanup;
    }
    err = EXIT_SUCCESS;
cleanup:
    close(cg_fd);
    //sockops_skel__destroy(skel);
    return err;
}
