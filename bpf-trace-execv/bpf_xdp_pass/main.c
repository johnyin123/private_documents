#include <net/if.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <unistd.h>
#include <bpf/bpf.h>
/* XDP_FLAGS_SKB_MODE */
#include <linux/if_link.h>
#include "mybpf_skel.h"

static int bpfverbose = 0;
static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args)
{
    if (level == LIBBPF_DEBUG && !bpfverbose)
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

int main(int argc, char **argv)
{
    struct mybpf_skel *skel;
    int err;

    if (argc != 2) {
        fprintf(stderr, "usage: %s <iface>\n", argv[0]);
        return EXIT_FAILURE;
    }
    const char *iface = argv[1];
    unsigned int ifindex = if_nametoindex(iface);
    if (!ifindex) {
        perror("failed to resolve iface to ifindex");
        return EXIT_FAILURE;
    }

    libbpf_set_print(libbpf_print_fn);
    if ((err = bump_memlock_rlimit())) {
        fprintf(stderr, "Failed to increase rlimit: %d", err);
        return 1;
    }
    if (!(skel = mybpf_skel__open())) {
        fprintf(stderr, "Failed to open BPF skeleton\n");
        return 2;
    }
    if ((err = mybpf_skel__load(skel))) {
        fprintf(stderr, "Failed to load and verify BPF skeleton\n");
        return 3;
    }
    /*Use "xdpgeneric" mode; less performance but supported by all drivers*/
    int flags = XDP_FLAGS_SKB_MODE;
    int fd = bpf_program__fd(skel->progs.xdp_prog);
    /* Attach BPF to network interface */
    err = bpf_set_link_xdp_fd(ifindex, fd, flags);
    if (err) {
        fprintf(stderr, "failed to attach BPF to iface %s (%d): %d\n", iface, ifindex, err);
        goto cleanup;
    }
    /* TODO: replace with actual code, e.g. loop to get data from BPF*/
    getchar();
    /* Remove BPF from network interface */
    fd = -1;
    err = bpf_set_link_xdp_fd(ifindex, fd, flags);
    if (err) {
        fprintf(stderr, "failed to detach BPF from iface %s (%d): %d\n",
            iface, ifindex, err);
        goto cleanup;
    }
 cleanup:
    mybpf_skel__destroy(skel);
    return err != 0;
}
